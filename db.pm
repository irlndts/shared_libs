package db;

# Библиотека функций для работы с БД

# check_db_connect			- проверяет соединение к БД и делаер реконнект при необходимости
# postgres_time_to_unix		- конвертирует время из БД postgres во время unixtime
# unix_time_to_postgres		- конвертирует время из unixtime в формат БД postgres
# PGArrayFromArray			- переводит массив в семантике perl в массив в семантике postgres

use strict;
use DBI;
use Data::GUID;

# Процедура контроля соединения к базе данных
# @param DBI $dbh
#	коннект к БД
# @param text $dbhost
#	хост для подключения
# @param text $dbport
#	порт для подключения
# @param text $dbname
#	имя базы данных
# @param text $dbuser
#	пользователь БД
# @param text $dbpass
#	пароль БД
# @param Integer $repeattime
#	сколько раз повторять попытку подключиться к бд
# @return DBI
#	Если соединение в порядке, возвращает тот-же DBI, который был в параметре $dbh
#	Если соединение разорвано, формируется новый коннект и возвращается новый объект DBI
sub check_db_connect {
	my ($dbh, $dbhost, $dbport, $dbname, $dbuser, $dbpass, $repeattime) = @_;

	if (!defined $repeattime) {$repeattime = 10;}

	# Проверка пингами
	while (!defined($dbh) || !$dbh->ping()) {
		if (defined($dbh)) {
			print STDERR "check_db_connect: NO db connect... restore\n";
			print STDERR ((defined($DBI::errstr))? $DBI::errstr:''), "\n";
			$dbh->disconnect;
			undef($dbh);
		};

		$dbh = DBI->connect("dbi:Pg:host=".$dbhost.";port=".$dbport.";dbname=".$dbname, $dbuser, $dbpass, {AutoCommit => 0, RaiseError => 0, PrintError => 0});

		# Провер после попытки соединения
		if (!defined($dbh) || !$dbh->ping()) {
			print STDERR "check_db_connect: can not restore db connect:\n";
			print STDERR ((defined($DBI::errstr))? $DBI::errstr:''), "\n";
			if (defined($repeattime) && ($repeattime > 0)) {
				sleep($repeattime);
			}
		};
	};
	return($dbh);
}

sub check_db_connect2 {
	my ($dbh, $dbhost, $dbport, $dbname, $dbuser, $dbpass, $repeattime) = @_;

	if (!defined $repeattime) {$repeattime = 10;};
	
	my $reconnect_count = 0;

	# Проверка пингами
	while (!defined($dbh) || !$dbh->ping()) {
		if (defined($dbh)) {
			print STDERR "check_db_connect: NO db connect... restore\n";
			print STDERR ((defined($DBI::errstr))? $DBI::errstr:''), "\n";
			$dbh->disconnect;
			undef($dbh);
		};

		$dbh = DBI->connect("dbi:Pg:host=".$dbhost.";port=".$dbport.";dbname=".$dbname, $dbuser, $dbpass, {AutoCommit => 0, RaiseError => 0, PrintError => 0});
		$reconnect_count ++;

		# Провер после попытки соединения
		if (!defined($dbh) || !$dbh->ping()) {
			print STDERR "check_db_connect: can not restore db connect:\n";
			print STDERR ((defined($DBI::errstr))? $DBI::errstr:''), "\n";
			if (defined($repeattime) && ($repeattime > 0)) {
				sleep($repeattime);
			};
		};
	};
	return($dbh, $reconnect_count);
};



# Перевести формат времени postgresql в формат времени unix
# @param String $ptime
#	<p>формат даты и времени в POSTGRESQL</p>
# @return
#	<p>
#		undef 	- Не удалось выполнить преобразование
#		integer	- преобразование было выполнено
#	</p>
sub postgres_time_to_unix {
	my ($ptime) = @_;

	my $utime = undef;
	if ($ptime =~ /^(\d{4})\-(\d{2})\-(\d{2}) (\d{2}):(\d{2}):(\d{2}).*$/) {
		$utime = mktime($6, $5, $4, $3, $2-1, $1-1900, 0, 0);
	};
	return($utime);
};

# Перевести формат времени unix в формат времени postgresql
# @param String $utime
#	<p>формат времени utime (UNIX)</p>
# @return
#	<p>
#		undef 	- Не удалось выполнить преобразование
#		integer	- преобразование было выполнено
#	</p>
sub unix_time_to_postgres {
	my ($utime) = @_;
	# Дата и время в формате ptime
	my $ptime = undef;
	$ptime = strftime('%Y-%m-%d %H:%M:%S', localtime($utime));
	return $ptime;
};

# Переводит массив в симмантике perl в массив в симмантике postgresql
# @param integer $type
#	<p>Тип выходных данных</p>
# @param String $elementType
#	<p>Выполнить приведение к заданному типу</p>
# @param Array $array
#	<p>Массив входных данных</p>
# @return String
#	<p>
#		строка 	- строка, для записи в базу
#		undef 	- не удалось выполнить преобразование
#	</p>
sub PGArrayFromArray {
	my $type = shift;
	my $elementType = shift;
	my $array = shift;

	# Временная строка данных
	my $shingleArrayInput = undef;
	my $startString = "array[";
	if($type == 2) {
		$startString = "{";
	}
	my $stopString = "]";
	if($type == 2) {
		$stopString = "}";
	}

	# Разобрать массив входных параметров
	foreach my $shingleValue (@{$array}) {
		# начало строки
		if (!defined $shingleArrayInput) {
			$shingleArrayInput .= $startString.$shingleValue;
			if(defined $elementType) {$shingleArrayInput .= "::".$elementType};
		} else {
			# если что-то есть уже в строке
			$shingleArrayInput .= ",".$shingleValue;
			if(defined $elementType) {$shingleArrayInput .= "::".$elementType};
		}
	}
	# Если массив пустой
	if(!$shingleArrayInput) {$shingleArrayInput .= $startString};
	$shingleArrayInput .= $stopString;
	return $shingleArrayInput;
};

# Генерация UUID
sub gen_uuid
{
    my $ug = new Data::GUID;

    my $uuid = lc($ug->as_string());

    return($uuid);
};

# выбрать список записей
sub get_list {
	my $dbh = shift;
	my $q = shift;
	my @p = @_;
	my $r = [];
	my $sth = $dbh->prepare($q);
	$sth->execute(@p);
	while (my $i = $sth->fetchrow_hashref()){
		push @$r, $i if $i;
	}
	return $r;
}

# выбрать следующее значеие последовательности: $id = db::nextval('transactions_id_seq');
sub nextval {
	my $dbh = shift;
	my $k = shift;
	my $r  = get_list($dbh,"select nextval('".$k."') as id");
	return $r->[0]->{id};
}

1;
