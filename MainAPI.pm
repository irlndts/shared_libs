#!/usr/bin/perl -w

# @tutorial Class Основные вспомогательыне фукнции проекта (независимые)
# @version 1.1.0
# @author CQSpel 2011
# @since
#        1.1.5
#             Чтение ini файла. readINI
#        1.1.0
#             Правка функции getPrevDateByMonth (Неверный год для now блока)
#        1.0.0
#             Основной функционал

package MainAPI;

use strict;
use vars qw($VERSION @ISA);
use locale;
use DBI;
use POSIX qw (locale_h);
use Config::IniFiles;

setlocale(LC_CTYPE, 'ru_RU.UTF-8');

	my $count = 0;
	$VERSION = "1.0";

	# Конструктор
	sub new {
		my $proto = shift;
		my $class = ref($proto) || $proto;
		my $count++;
		my $self = {};
		$self->{path} 		= '';
		$self->{scriptName} = '';
		$self->{config} 	= {};

		# Массив ошибок (для отладки)
		$self->{errors} 	= {};

		# Подключение к базе данных
		$self->{dbh} = undef;

		# инициализация ссылки на класс (объект)
		bless ($self,$class);
	}

	sub DESTROY {
		my $self = shift;
		$count--;
	}

	# Получает количество экземпляров класса
	# @return Integer 
	#	<p>
	#		количество экземпляров класса
	#	</p>
	sub getRefCount {
		return $count;
	}

	# Формирует путь к скрипту и записывает имя скрипта
	# @param String 
	#	<p>
	#		результат выполнений команды pwd
	#	</p>
	# @param String 
	#	<p>
	#		содержание переменной $0
	#	</p>
	#
	# @return void
	#	<p>
	#		формирует путь к рабочей дирректории
	#	</p>
	sub createPath {
		my $self 	= shift;

		# путь, полученный через команду pwd
		my $pwdTMP 	= shift;
		# путь, полученный в переменной $0
		my $_0TMP 	= shift;

		# Имя основного скрипта
		my $SNAME = $0;
		if ($SNAME =~ /([^\/]+)$/) {
			$SNAME = $1;
		}

		$self->{scriptName} = $SNAME;

		# Если вызов начинается с корня (/), значит не надо получать pwd
		if($_0TMP !~ /^\/([\.\.\/]*)/) {
			# результирующий путь
			my $pathTMP = '';

			my $numberOfRevert = undef;
			# Проверить $0 на наличие ..
			if($_0TMP =~ /^(\.\.\/[\.\.\/]*)/){
				# Посчитать количество вхождений подстроки ../ в строку
				$_ = $1;
				$numberOfRevert += s/..\///ig;
			}

			if($pwdTMP =~ /^([\w\\\/\_\-]+)[\s\S]+$/){
				$pwdTMP = $1;
			}

			if(($pwdTMP eq '\\')||($pwdTMP eq '/')){
				$pathTMP = "";
			} else {
				$pathTMP = $pwdTMP;
			}

			if($_0TMP =~ /^[\.\/]*([\w\/\_\-]+)\/[\w\-\_\.]*/) {
				$_0TMP = "/".$1;
			} else {
				$_0TMP = "";
			}

			# Проверить наличие открывающего слеша вначале строки
			if($_0TMP =~ /^[\_\-\w]+/){
				$_0TMP = "/".$_0TMP;
			}

			if ((defined $numberOfRevert)&&(defined $pathTMP)){
				# По шагам уменьшить $pathTMP
				my $i;
				for($i = 1;$i < length($pathTMP);$i++){
					my $tmpChar = substr($pathTMP, -$i,1);
					if($tmpChar eq '/'){$numberOfRevert--;}
					# В случае, когда в начале нет /
					if(($numberOfRevert == 1)&&($i == length($pathTMP))){$numberOfRevert = 0;}
					# Выйти из  цыкла обходчика
					if($numberOfRevert<=0){last();}
				}
				$pathTMP = substr($pathTMP,0,length($pathTMP) -$i);
			}

			# Проверить содержится ли pwd, как подстрока во второй строке по блока между /
			my @tmpStr = split('/',$pathTMP);
			my $found = undef;
			for(my $i=0;$i<@tmpStr;$i++){
				my $tmpStr2 = $tmpStr[$i];
				if(($tmpStr2 ne "")&&($_0TMP =~ /^[\.]*\/$tmpStr2\/[\s\w\/\.\_\-]*/)){
					$found = 1;
					last();
				}
			}

			if ((defined $pathTMP) &&(defined $found)){
				$pathTMP = $_0TMP;
			}else {
				(($_0TMP eq '\\')||($_0TMP eq '/')) ? $pathTMP .= "" : $pathTMP .= $_0TMP;
			}
			$self->{path} = $pathTMP;

			# Почистить временные переменные
			@tmpStr 	= undef;			
			$pathTMP 	= undef;
		} else {
			if($_0TMP =~ /^[\/]*([\w\/\_\-]+)\/[\w\-\_\.]*/){
				$_0TMP = "/".$1;
			} else {
				$_0TMP = "";
			}

			$self->{path} = $_0TMP;
		}

		# Почистить временные переменные
		$_0TMP 	= undef;
		$pwdTMP = undef;
	}

	# Получает путь к скрипту
	# @return String
	#	<p>
	#		Возвращает путь к рабочей дирреткории 
	#	</p>
	sub getPath {
		my $self = shift;
		return $self->{path};
	}

	# Получает имя основного скрипта
	# @return String
	#	<p>
	#		Возвращает путь к рабочей дирректории 
	#	</p>
	sub getScriptName {
		my $self = shift;
		return $self->{scriptName};
	}

	# Считывает значения конфига
	# @param String $fileName
	# <p>
	#	Имя файла конфигурации
	# </p>
	# @return Hash
	#	<p>
	#		Созадет хеш из значений конфига 
	#	</p>
	sub readConfig {
		my $self 		= shift;
		my $fileName 	= shift;
		# Прочитать файл конфига
		if (!defined $fileName) {
			open(CONFIG, $self->{path}."/profiler.conf") or $self->{error}[0] = "Can't open the config file";
		} else {
			open(CONFIG, $self->{path}."/".$fileName) or $self->{error}[0] = "Can't open the config file";
		}
		while (<CONFIG>) {
			# Обработать каждую строку
			if ($_ !~ /^[\s]*\#/) {
				# удалить все пробелы
				chomp;
				# распарсить строку параметров 
				if ($_ =~ /([\w\-\_]+)[\s]*\=[\s]*\'*\"*([\w\d\s\.\_\-\/\:\;\,\@\$\[\]\(\)\>\^\*\+\\\&\=]*)\'*\"*[\s]*\;*/){
					my $name 	= $1;
					my $value 	= $2;
					$self->{config}->{$name} = $value;
					# Установить версию
					if($1 =~ /^version$/i){
						$VERSION = $2;
					}
					# Обработка true, false
					if($value =~ /^true$/i){
						$self->{config}->{$name} = 1;
					} elsif ($value =~ /^false$/i){
						$self->{config}->{$name} = 0;
					}
				}
			}
		}
		close(CONFIG);
	}

	# Выводит значения переменных конфига
	# @return Hash
	#	<p>
	#		Возвращает хеш из значений конфига 
	#	</p>
	sub getConfig {
		my $self = shift;
		# Вывести содержимое конфига
		return $self->{config};
	}
	
	# Считывает ини файл с конфигом
	# @param String $fileName
	# <p>
	#	Имя файла конфигурации
	# </p>
	# @return Hash
	#	<p>
	#		Созадет хеш из значений конфига 
	#	</p>
	sub readINI {
		my $self 		= shift;
		my $fileName 	= shift;
		# Прочитать файл конфига
		my %ini;
		if (!defined $fileName) {
#			print $self->{path}."/configure.ini\n";
			tie %ini, 'Config::IniFiles', ( -file => $self->{path}."/configure.ini");
#			foreach my $text (@Config::IniFiles::errors) {
#				print $text>"\n";
#			}
		} else {
#			print $self->{path}."/".$fileName."\n";
			tie %ini, 'Config::IniFiles', ( -file => $self->{path}."/".$fileName);
#			foreach my $text (@Config::IniFiles::errors) {
#				print $text."\n";
#			}
		}
		# Проверка считанных данных
		if (!defined $ini{system}{active}) {
			$self->{error}->{readINI} = "Can't open the config file";
			return undef;
		}
		return %ini;
	}

	# Подключается к базе данных
	# @param String dbhost
	#	<p>
	#		ip адрес сервера баз данных 
	#	</p>
	# @param String dbname
	#	<p>
	#		имя базы данных 
	#	</p>
	# @param String dbuser
	#	<p>
	#		имя пользователя базы даных
	#	</p>
	# @param String dbuserPassword
	#	<p>
	#		пароль пользователя базы данных 
	#	</p>
	# @return void
	#	<p>
	#		1 - в случае успешной операции 
	#	</p>
	sub connectToTheDatabase {
		my $self = shift;
		my ($dbhost,$dbname,$dbuser,$dbuserPassword) = @_;
		# Дескриптор установленного соединения
		my $dbh;
		unless ($dbh = DBI->connect("dbi:Pg:host=$dbhost dbname=$dbname", $dbuser, $dbuserPassword, {AutoCommit => 1})) {
			$self->{errors}->{DBI} = "Can't connect to the database: ".$DBI::errstr;
			return undef;
		} else {
			$self->{dbh} = $dbh;
		}
		return 1;
	}

	# Получает ссылку на дескриптор подключения к базе данных
	# @return DBI
	#	<p>
	#		Возвращает дексриптор подключения к базе данных 
	#	</p>
	sub getDbh {
		my $self = shift;
		# Вывести содержимое конфига
		return $self->{dbh};
	}

	# Добавляет нового customers'а в базу данных подписок
	# @param msisdn VarChar(11)
	#	<p>Номер телефона абонента</p>
	# @return
	#	<p>
	#		integer - операция прошла успешно
	#		undef - не удалось добавить абонента в базу данных
	#	</p>
	sub addNewCustomer {
		my ($self,$msisdn,$oper) = @_;

		# Через хранимую процедуру
		# my $tmpSTH $self->{dbh}->prepare("select up_customers_ins(?, ?)");
		# $tmpSTH->execute($msisdn, $oper);
		# my ($tmpNewCustomerID) = $tmpSTH->fetchrow_array();
		# $tmpSTH->finish;
		# return $tmpNewCustomerID;
		

		# Выбрать следующий id из базы данных
		my $tmpSTH = $self->{dbh}->prepare("select nextval('customers_id_seq'::regclass) as nv");
		$tmpSTH->execute();

		# Идентификатор нового покупателя
		my $tmpNewCustomerID;
		unless (($tmpNewCustomerID) = $tmpSTH->fetchrow_array()) {
			$tmpSTH->finish();
			return undef;
		} else {
			$tmpSTH->finish();
			if(!defined $oper){
				# Получить оператора для абонента (чтобы вставить в базу данных)
				$oper = $self->getOperByMSISDN($msisdn);
			}
			if(!defined $oper){
				return undef;
			}
			# Добавить в базу нового покупателя
			unless ($self->{dbh}->do("INSERT INTO customers (id,msisdn,opid) VALUES (".$tmpNewCustomerID.",'$msisdn',".$oper->{id}.")")) {
				return undef;
			}
			$oper = undef;
			return $tmpNewCustomerID;
		}
	}

	# Определяет оператора по msisdn абонента
	# @param String msisdn
	#	<p>Номер телефона абонента</p>
	# @return
	#	<p>Массив:
	#		id 		- идентификатор оператора
	#		name 	- название региона
	#	</p>
	sub getOperByMSISDN {
		my $self = shift;
		my $msisdn = shift;
		my $oper = 0;
		my ($code, $def, $ssth) = ();

		# выделить из msisdn коде и 7 чисел диапазона
		if(length($msisdn)==11){
			$code = substr($msisdn,1,3);
			$def = substr($msisdn,4,7);
		}else{
			$code = substr($msisdn,0,3);
			$def = substr($msisdn,3,7);
		}

		# Запрос для определения оператора
		my $OPSQL = <<SQL;
SELECT op.id,cod.region FROM operators as op LEFT JOIN code_zones as cod ON cod.oper = op.id WHERE cod.code = ?
	and cod.def_start < ?
	and cod.def_stop > ?
SQL

		unless ($ssth = $self->{dbh}->prepare($OPSQL)) {
			return undef;
		}
		unless ($ssth->execute($code,$def,$def)) {
			return undef;
		}
		if ($ssth->rows() <= 0) {
			return undef;
		}
		unless ($oper = $ssth->fetchrow_hashref()) {
			return undef;
		}

		$ssth->finish;
		return $oper;
	}

		
	 # Получает год и месяц (- целое число месяцев от текущей даты)
	 # @param integer $year 
	 # 	<p>
	 # 		Год, относительно, которого необходимо выполнить расчет
	 # 	</p>
	 # @param integer $month 
	 # 	<p>
	 # 		Месяц, относительно, которого необходимо выполнить запрос
	 # 	</p>
	 # @param integer $months 
	 # 	<p>
	 # 		Целое число месяцев, которое необходимо вычесть из текущей даты
	 # 	</p>
	 # @return array <p>
	 # 		now -
	 # 			year	- текущий год
	 # 			month	- текущий месяц
	 # 		prev -
	 # 			year	- год за вычетом месяцев
	 # 			month	- месяц после вычета
	 # </p>
	sub getPrevDateByMonth {
		my $self 		= shift;
		my ($year,$month,$day,$months) = @_;
		
		# Получение предыдущего месяца простыми операторами
		my %outArray;

		# Массив информации о текущей дате и времени
		$outArray{'now'} 			= {};
		$outArray{'now'}{'day'} 	= $day;
		$outArray{'now'}{'month'} 	= $month;
		$outArray{'now'}{'year'} 	= $year;
	
		my $dateBefore = `date '+%Y-%m-%d' --date="(date) -1 day"`;
		if ((!defined $dateBefore)||(!$dateBefore)) {
			$dateBefore = `date -v-1d '+%Y-%m-%d'`;
		}
	
		$outArray{'prev'} 			= ();
		$outArray{'prev'}{'day'} 	= substr($dateBefore,8,2);
		$outArray{'prev'}{'month'} 	= substr($dateBefore,5,2);
		$outArray{'prev'}{'year'} 	= substr($dateBefore,0,4);
	
		my $dateBefore2 = `date '+%Y-%m-%d' --date="(date) -2 day"`;
		if ((!defined $dateBefore2)||(!$dateBefore2)) {
			$dateBefore2 = `date -v-2d '+%Y-%m-%d'`;
		}

		$outArray{'prev2'} 			= ();
		$outArray{'prev2'}{'day'} 	= substr($dateBefore2,8,2);
		$outArray{'prev2'}{'month'} = substr($dateBefore2,5,2);
		$outArray{'prev2'}{'year'} 	= substr($dateBefore2,0,4);
	
		my $dateBefore3 = `date '+%Y-%m-%d' --date="(date) -3 day"`;
		if ((!defined $dateBefore3)||(!$dateBefore3)) {
			$dateBefore3 = `date -v-3d '+%Y-%m-%d'`;
		}
		
		$outArray{'prev3'} 			= ();
		$outArray{'prev3'}{'day'} 	= substr($dateBefore3,8,2);
		$outArray{'prev3'}{'month'} = substr($dateBefore3,5,2);
		$outArray{'prev3'}{'year'} 	= substr($dateBefore3,0,4);
		return %outArray;
	}	

# Определяет оператора по msisdn абонента, используя платформу MNP
# @param String msisdn
#       <p>Номер телефона абонента</p>
# @return
#       <p>Массив:
#               billing_id      - идентификатор оператора в Биллинге
#               id                      - идентификатор оператора
#               region          - название региона
#       </p>
sub getOperByMSISDN_xMNP {
	my $msisdn = shift;
	my $response = undef;
	my $browser = undef;
	#my $mnp_url = "http://10.236.26.48:8080/mnp/msisdn/%msisdn%/json";
	my $mnp_url = "http://xmnp.proxy.megalabs.ru/mnp/msisdn/%msisdn%/json";
	my $content = "";
	my $msisdn_info = ();


	my $CodeToRef = { "1"  => "100", # МегаФон-Москва (СтФ)
		"6"  => "601", # МегаФон-Центр (ЦФ)
		"7"  => "200", # МегаФон-Поволжье (ПФ)
		"9"  => "800", # МегаФон-Дальний восток (ДвФ)
		"3"  => "500", # МегаФон-Северозападный филиал (СЗФ
		"5"  => "700", # МегаФон-Сибирь (СФ)
		"11" => "150", # МегаФон-Кавказ (КФ)
		"4"  => "900"  # МегаФон-Урал (УФ)
	};

	my $RefToCode = { "100" => "1",  # МегаФон-Москва (СтФ)
		"601" => "6",  # МегаФон-Центр (ЦФ)
		"200" => "7",  # МегаФон-Поволжье (ПФ)
		"800" => "9",  # МегаФон-Дальний восток (ДвФ)
		"500" => "3",  # МегаФон-Северозападный филиал (СЗФ
		"700" => "5",  # МегаФон-Сибирь (СФ)
		"150" => "11", # МегаФон-Кавказ (КФ)
		"900" => "4"   # МегаФон-Урал (УФ)
	};


	$browser = LWP::UserAgent->new;
	$browser->timeout(1);
	$mnp_url =~ s/%msisdn%/$msisdn/gi;
	if ((defined $msisdn) && ($msisdn ne "")) {
		$response = $browser->get($mnp_url);
		if ($response->{'_rc'} eq '200') {
			$content = $response->content();
			my $tmp_hash = js::to_hash($content);
			if ($tmp_hash->{Is_MegaFon} == 1) {
				$msisdn_info->{billing_id} = $tmp_hash->{Billing_id};
				$msisdn_info->{id} = $RefToCode->{$tmp_hash->{Billing_id}};
				$msisdn_info->{region} = $tmp_hash->{Location}->{Region_name};
			} else { 
				$msisdn_info->{billing_id} = -1;
				$msisdn_info->{id} = -1;
				$msisdn_info->{region} = ""; 
			};
		} else {
			$msisdn_info->{billing_id} = -1;
			$msisdn_info->{id} = -1;
			$msisdn_info->{region} = ""; 
		};
	} else {
		$msisdn_info->{billing_id} = -1;
		$msisdn_info->{id} = -1;
		$msisdn_info->{region} = ""; 
	}
	return $msisdn_info;
};

1;
