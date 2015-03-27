package dbm;

=comment
Class: Модернизированный класс для работы с БД
	Поддерживает множественные соединения, работу с репликациями, 
	логированием запросов и TODO: времени их выполнения.

# SHARED_CONFIGS/dbm/example.cfg - пимер конфигурационного файла для задания связей бд.

# Создание обьекта: 
my $DB = new dbm(dbs_file=>"/home/projects/SHARED_CONFIGS/dbm/example.cfg", default_base=>'repl_test');

Обозначения:
	Наименования баз могут быть 3 видов:
		Master bases: foo, bar, baz ...
		Slave bases: foo:s1, foo:s2, bar:s1, bar:s3 ...
		Default base: main, main:s1, main:s2, main:s4 ...
	
	Slave сервера именуются порядком следования в списске в конфигурационном файле.

=cut


use strict;
use DBI;
use Exporter;
use POSIX;
use Debug;
use Timer;
use vars qw/@ISA @EXPORT/;

@ISA = qw/Exporter/;
#@EXPORT = qw/DB_NOCOMMIT/;

=comment
Method: new
	Конструктор класса.

Parameters:
	dbs_file - Наименование файла со структурой баз данных которые нужно подключить. Структура в этом случае представляется в формате Perl структуры.
	app_conf - Хеш данных конфигурации приложения. В этой конфигурации обязательно должен присутствовать ключ "dbmstruct" значение которого задает связи мастер серверов со слейв серверами через префиксы в конфигурационном файле. Формат данных этого ключа:
	"prefix_master1; 
	 prefix_master2:
		slave_1,
		slave_2,...; 
	 prefix_master3; 
	 prefix_master4;
	 ...
	"
	В большинстве случаев это может выглядеть так:
	"hex:hex_s1,hex_s2,hex_s3; cms:cms_s"

	Соответственно в конфиге приложения должны быть блоки параметров с префиксами:
	hex_dbname ...
	hex_s1_dbname ...
	cms_dbname ...
	cms_s_dbname и. т .д.

	default_base - какую по умолчанию базу использовать

Returns:
	Объект.

Example:
	new dbm(dbs_file=>"/home/projects/SHARED_CONFIGS/dbm/example.cfg", default_base=>'repl_test')

=cut

sub new {
	my $class = shift;
	my $this = {
		# по умолчанию все запросы идут именно через эту бд
		default_base=>undef,
		dbs_file=>'',
		app_conf=>undef,
		@_
	};
	$this->{DBS} = {};
	# Если передали данные конфига приложения, формируем труктуру на основе этих данных.
	my $dbs = undef;
		
	if (defined $this->{app_conf} && ref $this->{app_conf} eq 'HASH' && exists $this->{app_conf}{dbmstruct}){
		$dbs = composeStructByConfData($this->{app_conf});
		debug "Compose DBS struct DEBUG: ",$dbs;
	}

	if ($this->{dbs_file} or defined $this->{app_conf}){
		# конфиг с описанием баз данных и их связей
		unless (defined $dbs){
			if ($this->{dbs_file}){
				$dbs = read_config($this->{dbs_file});
			}
		}

		if (defined $dbs && ref $dbs eq 'HASH'){
			# содержит единственную структуру обходимся без цикла
			$this->{DBS}{$dbs->{name}} = {};
			compose_dbs($dbs,\$this->{DBS}{$dbs->{name}});
			if (exists $dbs->{slaves} && ref $dbs->{slaves} eq 'ARRAY' ){
				$this->{DBS}{$dbs->{name}}{slaves} = [];
				foreach my $sl (@{$dbs->{slaves}}){
					my $s = {};
					$sl->{name} = $dbs->{name} unless $sl->{name};
					compose_dbs($sl,\$s);
					push @{$this->{DBS}{$dbs->{name}}{slaves}},$s;
				}
			}
			$this->{default_base} = $dbs->{name};
		}elsif(defined $dbs && ref $dbs eq 'ARRAY' ){
			# конфиг представлен списком
			$this->{default_base} = $dbs->[0]->{name} unless $this->{default_base};
			foreach my $d (@$dbs){
				debug "finded base:".$d->{name};
				$this->{DBS}{$d->{name}} = {};
				compose_dbs($d,\$this->{DBS}{$d->{name}});
				#debug "compose data for ".$d->{name}.':',$this->{DBS}{$d->{name}};
				if (exists $d->{slaves} && ref $d->{slaves} eq 'ARRAY' ){
					$this->{DBS}{$d->{name}}{slaves} = [];
					foreach my $sl (@{$d->{slaves}}){
						my $s = {};
						$sl->{name} = $d->{name} unless $sl->{name};
						compose_dbs($sl,\$s);
						push @{$this->{DBS}{$d->{name}}{slaves}},$s;
					}
				}
			}
		}else{
			debug (" DBSYS | Bad config file format: \"$this->{dbs_file}\" or Bad \"app_conf\" data file.");
			return undef;
		}
		# устанавливаем базу по умолчанию
		unless (exists $this->{DBS}{$this->{default_base}}){
			debug (" DBSYS | Not found default database: \"$this->{default_base}\"");
			return undef;
		}
		$this->{DBS}{main} = $this->{DBS}{$this->{default_base}};
	}else{
		debug (" DBSYS | Not readable or not found file: \"$this->{dbs_file}\" or Bad \"app_conf\" data.");
		return undef;
	}
#	debug "STRUCT:",$this->{DBS};

	bless $this,$class;
	return $this;
}

=comment
Method: reinit 
	Перепроверить соединения с БД.
	Делает рекконект, к имеющимся базам. Заодно делаем rollback, если стало ясно что с базой commit не пройдет.

Parameters:
	Наименования БД, которые надо переинициализировать.	
	Без параметров - переподключить все доступные базы: 

Returns:
	1 - Параметр: статус
	OK - В случае если все мастер базы работают.
	WARN - Произошли проблемы с соединением к slave серверам.
	ERROR - Одна или несколько мастер баз отвалилась.
	2 - Детализация: что именно неудалось инициализировать.

Example:
	$db->reinit(base1,base2,base3) - инициализирует соединения по базам base1,base2,base3.
	$db->reinit() - инициализирует соединения по всем имеющимся базам.

=cut

sub reinit {
	my dbm $this = shift;
	my @bases = @_;
	my $ans = 'OK';
	my $err = [];
	@bases = $this->dblist unless @bases;
	foreach my $m (@bases){
		debug "connect_cached", $this->{DBS}{$m}{_connect_opt_} if $m eq 'cms';
		if ($this->{DBS}{$m}{dbh} = DBI->connect_cached(@{$this->{DBS}{$m}{_connect_opt_}})){
			debug "check connect to database: ".$m." OK.";
			# подняли мастер соединение, проверяем его slaves:
			if (exists $this->{DBS}{$m}{slaves} && ref $this->{DBS}{$m}{slaves} eq 'ARRAY'){
				my $sc = 0;
				foreach my $sl (@{$this->{DBS}{$m}{slaves}}){
					if ($sl->{dbh} = DBI->connect_cached(@{$this->{DBS}{$m}{slaves}->[$sc]->{_connect_opt_}})){
						debug "check connect to database: ". $m.":s".($sc+1)." OK.";
					}else{
						# что то со слейвом не так, откатываем этот slave, но исключительной ситуации не генерируем.: 
						debug ("DBSYS | ".$DBI::errstr);
						$ans = 'WARN';
						push @$err,'slave:'.$m.':s'.($sc+1);
					}
					$sc++;
				}
			}
		}else{
			debug ("DBSYS | ".$DBI::errstr);
			$ans = 'ERR';
			push @$err, 'master:'.$m;
		}
	}
	return ($ans,$err);
}

sub read_config {
	my $f = shift;
	my $r = undef;
	if (-r $f){
		unless ($r = do($f)){
			debug (" DBSYS | Failure parse file \"$f\" :".$@);
			return undef;
		}
		return $r;
	}
	debug (" DBSYS | Not readable or not found file: \"$f\"");
	return undef;
}

sub rollback {
	my dbm $this = shift;
	my @lb = @_;
	# если нет пареметров - откатываем по всем соединениям:
	@lb = $this->dblist(add_slaves=>1,only_active=>1) unless @lb;	
	foreach my $base (@lb){
		my ($m,$s) = $this->split_name($base);
		unless (exists $this->{DBS}{$m}{_autocommit_} && $this->{DBS}{$m}{_autocommit_}){
			next if $this->opts_autocommit($base);
			$this->dbh($base)->rollback();
		}
	}
}

=comment
Method: commit
	Закрепить изменения в базе.

Parameters: 
	Список баз в которых необходимо сделать коммит.
	Без параметров - сделать везде.

Returns:
=cut

sub commit {
	my dbm $this = shift;
	my @lb = @_;
	# если нет пареметров - откатываем по всем соединениям:
	@lb = $this->dblist(add_slaves=>1,only_active=>1) unless @lb;	
	foreach my $base (@lb){
		next if $this->opts_autocommit($base);
		$this->dbh($base)->commit();
	}
}

=comment
Method: disconnect
	Отсоединиться от баз.

Parameters:
	Cписок баз из dblist	

Returns:

=cut

sub disconnect {
	my dbm $this = shift;
	my @lb = @_;
	# если нет пареметров - откатываем по всем соединениям:
	@lb = $this->dblist(add_slaves=>1,only_active=>1) unless @lb;	
	foreach my $base (@lb){
		$this->dbh($base)->disconnect();
	}
}

=commnet
Method: dbh
	Вернуть простой хендлер соединения с бд.

Parameters:
	$dbase - наименование базы к которой нужно получить handler.
	если не передан - возвращается dbh для main базы.

Returns:
	$dbh

Example:
	# вернуть хендлер на мастер базу foo
	my $dbh_foo = $DBM->dbh('foo');

	# вернуть хендлер на вторую slave базу foo
	my $dbh_foo_slave1 = $DBM->dbh('foo:s2');

=cut

sub dbh {
	my dbm $this = shift;
	my $base = shift || 'main';
	my ($m,$s) = $this->split_name($base);
	unless ($s && $s =~ /^\d+$/){
		return $this->{DBS}{$m}{dbh};
	}
	return $this->{DBS}{$m}{slaves}->[$s-1]->{dbh};
}

sub compose_dbs {
	my ($dbp,$v) = (shift,shift);
	$$v = {
			dbh=>undef,
			_dbname_=>$dbp->{name},
			_connect_opt_=>['dbi:Pg:dbname='.$dbp->{name}.
				(exists $dbp->{host} ? ';host='.$dbp->{host} : '').
				(exists $dbp->{port} ? ';port='.$dbp->{port} : ''),
				(exists $dbp->{user} ? $dbp->{user} : 'postgres'),
				(exists $dbp->{pass} ? $dbp->{pass} : '')
			]
	};
	
	if (exists $dbp->{opts} && ref $dbp->{opts} eq 'HASH'){
		push @{$$v->{_connect_opt_}}, $dbp->{opts};
		$$v->{_autocommit_} = $dbp->{opts}{AutoCommit} if exists $dbp->{opts}{AutoCommit};
	}else{
		push @{$$v->{_connect_opt_}}, {AutoCommit => 0};
		$$v->{_autocommit_} = 0;
	}
}

=comment
Method: dblist 
	Показать список всех баз, содержащихся в обьекте.

Parameters:
	add_slaves - отобразить slave базы.	
	only_active - только подключенные базы.
Returns:

=cut

sub dblist {
	my dbm $this = shift;
	my %p = (add_slaves=>undef,only_active=>undef,@_);
	my @lb = ();
	if (defined $p{only_active}){
		map {push @lb, $_ if ($_ ne 'main' && $this->dbh($_))} keys %{$this->{DBS}};
		if (defined $p{add_slaves}){
			# add slaves base:
			my @b = @lb;
			foreach my $m (@b){
				if (exists $this->{DBS}{$m}{slaves} && @{$this->{DBS}{$m}{slaves}}){
					for (0..$#{$this->{DBS}{$m}{slaves}}){
						push @lb, $m.':s'.($_+1) if $this->dbh($m.':s'.($_+1)) ;
					}
				}
			}
		}
	}else{
		map {push @lb, $_ if ($_ ne 'main')} keys %{$this->{DBS}};
		if (defined $p{add_slaves}){
			# add slaves base:
			my @b = @lb;
			foreach my $m (@b){
				if (exists $this->{DBS}{$m}{slaves} && @{$this->{DBS}{$m}{slaves}}){
					push @lb, $m.':s'.($_+1) for (0..$#{$this->{DBS}{$m}{slaves}});
				}
			}
		}
	}
	return @lb;
}

=comment
Method: Подготовить запрос с учетом проксирования. 
	Анализ запросов прост, Если не указанокуда именно кидать запросу,
	пытаемся догадаться по первому слову.

Parameters:
	$query - запрос

Returns
	$sth запроса.

=cut

sub prepare {
	my dbm $this = shift;
	my @q = @_;
	debug "DB: ",@q; 
	my $sth = undef;
	if (is_sel($q[0]) && exists $this->{DBS}{main}{slaves}){
		# запрос типа select
		my $s = $this->select_slave_num();
		debug "selected main:s".($s)." slave server";
		$sth = $this->dbh("main:s".$s)->prepare(@q);
		$this->s_cnt_inc("main:s".$s);
	}else{
		# иные запросы выполняем на мастере
		debug "selceted master server";
		$sth = $this->dbh()->prepare(@q);
	}
	return $sth;
}

=comment
Method: read_list
	Прочитать список значений. Запросы отправляются только к slave серверам еси они есть.

Parameters:
	$dbname -  наименование базы к которой сделать запрос. 
				undef - означает взять main базу,
				main:s - сделать запрос к слейв серверу main базы даннх.
				foo	- сделать запрос к слейв серверу базы данных foo.
	
	$query - запрос.
	@params - Параметры запроса.

Returns:
	
=cut

sub read_list {
	my $this = shift;
	my $base = shift || 'main';
	my $q = shift;
	my @p = @_;
	my $r = [];
	tic('QTIME');

	# разбиваем наименование базы, с добавлением выбора slave сервера:
	my ($b, $s) = $this->split_name($base,auto_slave_num=>1);

	my $sth = undef;
	if ($s && $s =~ /^\d+$/){
		# запрос на slave
		debug "selected slave server:";
		$sth = $this->dbh($b.":s".$s)->prepare($q);
	}else{
		# иные запросы выполняем на мастере
		debug "selceted master server",$b;
		$sth = $this->dbh($b)->prepare($q);
	}

	$sth->execute(@p);
	$this->s_cnt_inc($b.":s".$s) if $s;

	while (my $i = $sth->fetchrow_hashref()){
		push @$r, $i if $i;
	}
	toc('QTIME');
	debug $q.' | params: (\''.(join "\',\'",@p).'\') | Time:'.tictoc('QTIME');
	tic_clear('QTIME');
	return $r;
}

=comment
Method: dbexec
	Выполнить запрос.

Parameters:
	$basename - если undef то main
	$q - запрос
	@p - параметры запроса

Returns:

=cut

sub dbexec {
	my $this = shift;
	my $b = shift || 'main';
	my $q = shift;
	my @p = @_;
	tic('QTIME');
	my $sth = $this->dbh($b)->prepare($q);
	$sth->execute(@p) or debug "DBERR | ", $this->dbh($b)->errstr();
	toc('QTIME');
	debug $q.' | params: (\''.(join "\',\'",map {(defined $_ ? $_ : 'NULL')} @p).'\') | Time:'.tictoc('QTIME');
	tic_clear('QTIME');
}

=comment
Method: do
	Выполнить запрос с учетом проксирования

Parameters:
	Такие же как и с $dbh->do();

Returns:

=cut

sub do {
	my dbm $this = shift;
	my @q = @_;
	my $sth = undef;
	debug "DB: ",\@q; 
	if (is_sel($q[0])){
		my $s = $this->select_slave_num();
		debug "selected main:s".($s)." slave server";
		$this->s_cnt_inc("main:s".$s);
		return $this->dbh("main:s".$s)->do(@q);
	}else{
		debug "selceted master server";
		return $this->dbh()->do(@q); 
	}
}

sub is_sel {
	my $q = shift;
	return 1 if $q =~ /^\s*select\b/i;
}

=comment
Method: select_slave_num
	Выбрать номер slave сервера.
	Реализован только равномерное распределение запросов по серверам.

Parameters:
	$base - Наименование мастер базы.

Returns:
	$num - номер 
	TODO: выбирать slave  в зависимости от количества запросов, ли бо по весам.

=cut

sub select_slave_num {
	my dbm $this = shift;
	my $base = shift || 'main';
	# если количество обращений к одному больше чем к другому - выбираем меньший.
	my $less = undef;
	my $max_cnt = 1e+12;
	my ($c,$qc) = (0,undef);
	foreach (@{$this->{DBS}{$base}{slaves}}){
		$c++;
		next unless $_->{dbh};
		unless (exists $_->{qcount}){
			$less = $c;
			return $less;
		}else{
			# сбрасываем счетчик запросов от греха подальше.
			$_->{qcount} = 0 if ($_->{qcount} >= $max_cnt);
			unless (defined $qc){
				$qc = $_->{qcount};
				$less = $c;
				next;
			}
			if($_->{qcount} < $qc){
				# последующий слейв сервер имеет меньшее количество обращений:
				$less = $c;
			}
		}
	}
	return $less;
	#return sprintf("%1.f", ((rand ($#{$this->{DBS}{$base}{slaves}}) + 1)) );
}

# увеличить счетчик запросов к slave серверу
sub s_cnt_inc {
	my dbm $this = shift;
	my $ds = $this->_slave(shift || 'main:s1');
	$$ds->{qcount}++;
}

# сбросить счетчик обращений к slave серверу.
sub s_cnt_res {
	my dbm $this = shift;
	my $ds = $this->_slave(shift || 'main:s1');
	delete $$ds->{qcount};
}

# просмотреть количество обращений к slave серверу:
sub s_cnt {
	my dbm $this = shift;
	my $ds = $this->_slave(shift || 'main:s1');
	return $$ds->{qcount};
}

# разбить принятое наименование базы в мастер и слейв обозначение.
=comment
Method: split_name
	Разбивает строку указателя на базу и номер слейва.

Parameters:
	$n - строка
	auto_slave_num - Сгенерировать автоматически номер слейв сервера в случае если передана строка в виде: foo:s

Returns:
	$b - наименование базы
	$n - номер слейв базы.

=cut

sub split_name {
	my $this = shift;
	my $n = shift;
	my %o = (auto_slave_num=>undef,@_);
	my ($b,$s) = (split /:s/, $n);
	
	if (defined $o{auto_slave_num}){
		if ($n =~ /:s$/ && exists $this->{DBS}{$b}{slaves}){
			# выбрать любой слейв базы
			$s = $this->select_slave_num();
			debug "selected main:s".($s)." slave server";
		}
	}
	
	return ($b,$s);
}

# получить настройки slave сервера
sub _slave {
	my dbm $this = shift;
	my $name = shift;
	my ($m,$s) = $this->split_name($name);
	return undef if  ($s > ($#{$this->{DBS}{$m}{slaves}} + 1));
	return \$this->{DBS}{$m}{slaves}->[$s-1] if exists $this->{DBS}{$m}{slaves};
}

# просмотреть режим автокоммита в базе
sub opts_autocommit {
	my dbm $this = shift;
	my $b = shift;
	# если есть autocommit и он 0 - то автокоммит отключен
	my ($m,$s) = $this->split_name($b);
	unless ($s){
		# мастер база
		return 0 if (exists $this->{DBS}{$m}{_autocommit_} && $this->{DBS}{$m}{_autocommit_} == 0);
	}else{
		# slave база 
		my $sl = $this->_slave($b);
		return 0 if (exists $$sl->{_autocommit_} && ($$sl->{_autocommit_} == 0));
	}
	return 1;
}	

=comment
Method: default_base 
	Установыить, базу по умолчанию. Иначе говоря - main базу.

Parameters:
	$base - обозначение master базы

Returns:
	Если аргументы не переданы - возвращает имя базы по умолчанию.
	Если аргумент есть - устанавливаем.

=cut

sub default_base {
	my dbm $this = shift;
	unless (@_){
		return $this->{default_base};
	}else{
		my $b = shift;
		debug " set default base:",$b;
		$this->{default_base} = $b;
		$this->{DBS}{main} = $this->{DBS}{$b};
	}
}

=nd
Method: composeStructByConfData
	Собрать структуру связей баз данных на основе данных конфигурацилнного файла приложения.

Parameters:
	$data  - данные конфига приложения.

Returns:
	Perl структуру связей.

=cut

sub composeStructByConfData {
	my $conf = shift;
	my $res = [];
	
	foreach (split /;/,$conf->{dbmstruct}){

		my $m = {};
		if ($_=~/^(\w+)\:(\w+)$/){
			$m = {
				name=>$conf->{$1.'_dbname'},
				host=>$conf->{$1.'_dbhost'},
				port=>$conf->{$1.'_dbport'},
				user=>$conf->{$1.'_dbuser'},
				pass=>$conf->{$1.'_dbuserPassword'},
				slaves=>[]
			};
			# если есть : значит есть slave серверы
			foreach my $s (split /,/,$2){
				push @{$m->{slaves}}, {
					name=>$conf->{$s.'_dbname'},
					host=>$conf->{$s.'_dbhost'},
					port=>$conf->{$s.'_dbport'},
					user=>$conf->{$s.'_dbuser'},
					pass=>$conf->{$s.'_dbuserPassword'},
				}
			}
		}elsif($_ =~ /^(\w+)$/){
			$m = {
				name=>$conf->{$1.'_dbname'},
				host=>$conf->{$1.'_dbhost'},
				port=>$conf->{$1.'_dbport'},
				user=>$conf->{$1.'_dbuser'},
				pass=>$conf->{$1.'_dbuserPassword'},
			};
		}
		push @$res,$m  if %$m;
	}

	return $res;
}

1;
