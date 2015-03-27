#!/usr/bin/perl -w

# @copyright CQSpel 2011
# Class
# 	Работа с хранилищем платежей
package PaysAPI;

use strict;
use vars qw($VERSION @ISA);
use locale;
use DBI;
use POSIX qw (locale_h);
setlocale(LC_CTYPE, 'ru_RU.UTF-8');

	my $count = 0;
	$VERSION = "1.0";

	# Конструктор
	sub new {
		my $proto 	= shift;
		#my $Log 	= shift;
		my $class = ref($proto) || $proto;
		my $count++;
		my $self = {};
		$self->{tables} 	= {};

		# Массив ошибок (для отладки)
		$self->{errors} 	= {};
		
		# Логирование
		#$self->{log} 	= $Log;
		

		# инициализация ссылки на класс (объект)
		bless ($self,$class);
	}

	sub DESTROY {
		my $self = shift;
		$count--;
	}

	# Получает список патиций для платежей
	# @param MainAPI $mainAPI
	#	<p>Экземпляр класса основных функций</p>
	# @param DecisionMaker $DCM
	#	<p>Экземпляр класса принятия решения</p>
	# @return
	#	<p>
	#		1 - операция прошла успешно
	#		undef - не удалось получить список таблиц
	#	</p>
	sub getPartitionsList {
		my ($self,$mainAPI) = @_;
		# Инициализация переменных
		my ($sth) = ();

		if (defined $mainAPI) {
				# Выбрать все патиции
				my $query = "
SELECT pg_t.tablename 
	FROM pg_tables as pg_t
	WHERE tablename like 'pays_%'
	ORDER BY tablename
";
				# Выполнить запрос
				unless ($sth = $mainAPI->{dbh}->prepare($query)) {
					$self->{errors}->{DBI} = "Не удалось подготовить запрос на определение списка таблиц платежей";
					$sth->finish();
					return undef;
				}

				unless ($sth->execute()) {
						$self->{errors}->{DBI} = "Не удалось выполнить запрос на извлечение списка активных таблиц платежей";
						$sth->finish();
						return undef;
				};

				if($sth->rows() > 0) {
					while (my $row = $sth->fetchrow_hashref()) {
						my @yearMonthArray 	= split('_',$row->{tablename});
						if ((defined ($yearMonthArray[1]))&&(defined ($yearMonthArray[2]))) {
							if (defined ($yearMonthArray[3])) {
								$self->{tables}->{$yearMonthArray[1]."_".$yearMonthArray[2]."_".$yearMonthArray[3]} = $yearMonthArray[1]."-".$yearMonthArray[2]."-".$yearMonthArray[3];
							} else {
								$self->{tables}->{$yearMonthArray[1]."_".$yearMonthArray[2]} = $yearMonthArray[1]."-".$yearMonthArray[2];
							}
						}
					}
					return 1;
				} else {
					return undef;
				}
		} else {
			return undef;
		}
	}

	# Добавляет таблицу платежей в базу (физически)
	# @param MainAPI $mainAPI
	#	<p>Экземпляр класса основных функций</p>
	# @param timestamp $date
	#	<p>Дата, из которой будет выделен месяц и год и прозведено удаление таблицы</p>
	# @return
	#	<p>
	#		1 - операция прошла успешно
	#		undef - не удалось добавить таблицу
	#	</p>
	sub addPartition {
		my ($self,$mainAPI,$date) = @_;
		# Инициализация переменных
		my ($sth) = ();
		my ($sec,$min,$hour,$currentmday,$currentmon,$currentyear,$wday,$yday,$isdst) = localtime(time);
		my $yearMonth;

		# Если не задана дата, значит, взять текущую
		if (!defined $date) {
			$currentmon = ($currentmon+1);
			$currentmday = sprintf "%02d",$currentmday;
			$currentmon = sprintf "%02d",$currentmon;
			$currentyear = $currentyear+1900;
			$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
		} else {
			# выделить год и месяц
			$currentyear = substr($date,0,4);
			$currentmon = substr($date,5,2);
			$currentmday 	= substr($date,8,2);

			$currentmon = sprintf "%02d",$currentmon;
			$currentmday 	= sprintf "%02d",$currentmday;

			$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
		}

		# Проверить наличие подключения и удалить патицию
		if (defined $mainAPI) {
			my $query = "SELECT logs.checkcreate_pays_tablename(?);";
			# Выполнить запрос
			unless ($sth = $mainAPI->{dbh}->prepare($query)) {
				$self->{errors}->{DBI} = "Не удалось подготовить запрос на добавление таблицы платежей";
				$sth->finish();
				return undef;
			}
			unless ($sth->execute($yearMonth)) {
					$self->{errors}->{DBI} =  "Не удалось выполнить запрос на добавление таблицы платежей";
					$sth->finish();
					return undef;
			};
		}
		if ($self->addPartitionToCache($date)) {
			return 1;
		} else {
			return undef;
		}
	}

	# Удаляет физически таблицу платежей
	# @param MainAPI $mainAPI
	#	<p>Экземпляр класса основных функций</p>
	# @param timestamp $date
	#	<p>Дата, из которой будет выделен месяц и год и прозведено удаление таблицы</p>
	# @return
	#	<p>
	#		1 - операция прошла успешно
	#		undef - не удалось удалить запись
	#	</p>
	sub delPartition {
		my ($self,$mainAPI,$date) = @_;
		# Инициализация переменных
		my ($sth) = ();
		my ($sec,$min,$hour,$currentmday,$currentmon,$currentyear,$wday,$yday,$isdst) = localtime(time);
		my $yearMonth;

		# Если не задана дата, значит, взять текущую
		if (!defined $date) {
			$currentmon = ($currentmon+1);
			$currentmday = sprintf "%02d",$currentmday;
			$currentmon = sprintf "%02d",$currentmon;
			$currentyear = $currentyear+1900;
			$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
		} else {
			# выделить год и месяц
			$currentyear 	= substr($date,0,4);
			$currentmon 	= substr($date,5,2);
			$currentmday 	= substr($date,8,2);

			$currentmon = sprintf "%02d",$currentmon;
			$currentmday 	= sprintf "%02d",$currentmday;

			$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
		}

		# Проверить наличие подключения и удалить патицию
		if (defined $mainAPI) {
			my $query = "DROP TABLE IF EXISTS logs.pays_".$yearMonth.";";
			# Выполнить запрос
			unless ($sth = $mainAPI->{dbh}->prepare($query)) {
				$self->{errors}->{DBI} = "Не удалось подготовить запрос на удаление патиции таблицы платежей";
				$sth->finish();
				return undef;
			}
			unless ($sth->execute()) {
					$self->{errors}->{DBI} = "Не удалось выполнить запрос на удаление патиции таблицы платежей";
					$sth->finish();
					return undef;
			};
		}
	}

	# Удаляет информацию об активной таблице в хеше таблиц
	# @param timestamp $date
	#	<p>Дата, из которой будет выделен месяц и год и прозведено удаление таблицы</p>
	# @return
	#	<p>
	#		1 - операция прошла успешно
	#		undef - не удалось удалить запись
	#	</p>
	sub delPartitionFromCache {
		my ($self,$date) = @_;

		# Инициализация переменных
		my ($sth) = ();
		my ($sec,$min,$hour,$currentmday,$currentmon,$currentyear,$wday,$yday,$isdst) = localtime(time);
		my $yearMonth;

		# Если не задана дата, значит, взять текущую
		if (!defined $date) {
			$currentmon = ($currentmon+1);
			$currentmday = sprintf "%02d",$currentmday;
			$currentmon = sprintf "%02d",$currentmon;
			$currentyear = $currentyear+1900;
			$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
		} else {
			# выделить год и месяц
			$currentyear 	= substr($date,0,4);
			$currentmon 	= substr($date,5,2);
			$currentmday 	= substr($date,8,2);

			$currentmon = sprintf "%02d",$currentmon;
			$currentmday 	= sprintf "%02d",$currentmday;

			$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
		}

		if (defined $self->{tables}->{$yearMonth}) {
			$self->{tables}->{$yearMonth} = undef;
			delete($self->{tables}->{$yearMonth});
			return 1;
		} else {
			return undef;
		}
	}

	# Добавляет информацию об активной таблице в хеше таблиц
	# @param timestamp $date
	#	<p>Дата, из которой будет выделен месяц и год и прозведено добавление таблицы в кеш</p>
	# @return
	#	<p>
	#		1 - операция прошла успешно
	#		undef - не добавить запись
	#	</p>
	sub addPartitionToCache {
		my ($self,$date) = @_;

		# Инициализация переменных
		my ($sth) = ();
		my ($sec,$min,$hour,$currentmday,$currentmon,$currentyear,$wday,$yday,$isdst) = localtime(time);
		# Дата и время в разном формате
		my ($yearMonth,$yearMonth2) = ();

		# Если не задана дата, значит, взять текущую
		if (!defined $date) {
			$currentmon = ($currentmon+1);
			$currentmday = sprintf "%02d",$currentmday;
			$currentmon = sprintf "%02d",$currentmon;
			$currentyear = $currentyear+1900;
			$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
			$yearMonth2 = $currentyear."-".$currentmon."-".$currentmday;
		} else {
			# выделить год и месяц
			$currentyear = substr($date,0,4);
			$currentmon = substr($date,5,2);
			$currentmday 	= substr($date,8,2);

			$currentmon = sprintf "%02d",$currentmon;
			$currentmday 	= sprintf "%02d",$currentmday;

			$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
			$yearMonth2 = $currentyear."-".$currentmon."-".$currentmday;
		}

		if (!defined $self->{tables}->{$yearMonth}) {
			$self->{tables}->{$yearMonth} = $yearMonth2;
			return 1;
		} else {
			return undef;
		}
	}

	# Добавляет информацию об активной таблице в хеше таблиц
	# @param MainAPI $mainAPI
	#	<p>Экземпляр класса основных функций</p>
	# @param bigint $msisdn
	#	<p>Номер телефона абонента</p>
	# @param integer $timeout
	#	<p>Таймаут в минутах</p>
	# @return
	#	<p>
	#		1 - разрешено выполнение операции. Таймаут истек
	#		undef - таймаут не истек. Выполнение операции запрещено
	#	</p>
	sub checkNextCommandTimeout {
		my ($self,$mainAPI,$msisdn,$timeout) = @_;

		# Инициализация переменных
		my ($sth) = ();
		my ($sec,$min,$hour,$currentmday,$currentmon,$currentyear,$wday,$yday,$isdst) = localtime(time);
		# Дата и время в разном формате
		my ($yearMonth,$yearMonth2) = ();

		$currentmon 	= ($currentmon+1);
		$currentmday = sprintf "%02d",$currentmday;
		$currentmon 	= sprintf "%02d",$currentmon;
		$currentyear 	= $currentyear+1900;
		$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
		$yearMonth2 = $currentyear."-".$currentmon."-".$currentmday;

		my %prevDate = $mainAPI->getPrevDateByMonth($currentyear,$currentmon,$currentmday);

		if (defined $self->{tables}->{$yearMonth}) {
			my $query = "SELECT p.id FROM logs.pays as p
LEFT JOIN customers as c ON c.id = p.custid
WHERE
	c.msisdn = ?
	and ((date(p.paydate) = '".$yearMonth2."'::date)
		or (date(p.paydate) = '".$prevDate{prev}{year}."-".$prevDate{prev}{month}."-".$prevDate{prev}{day}."'::date))
	and p.paydate >= (now()-'".$timeout." second'::interval);";
			# Выполнить запрос
			unless ($sth = $mainAPI->{dbh}->prepare($query)) {
				$sth->finish();
				return undef;
			}

			unless ($sth->execute($msisdn)) {
					$sth->finish();
					return undef;
			};

			# Если запись есть, значит, не разрешать выполнять дейсвтияе - undef, если записи нет - вернуть 1 
			if($sth->rows() > 0) {return undef;} else {return 1;}
		} else {
			return 1;
		}
	}

	# Добавляет запись в таблицу платежей
	# @param MainAPI $mainAPI
	#	<p>Экземпляр класса основных функций</p>
	# @param bigint $sid
	#	<p>идентификатор подписки или идентификатор глобального сервиса</p>
	# @param bigint $custid
	#	<p>идентификатор абонента</p>
	# @param bigint $result
	#	<p></p>
	# @param bigint $tid
	#	<p></p>
	# @param bigint $paydate
	#	<p></p>
	# @param bigint $filname
	#	<p>название партнера</p>
	# @return
	#	<p>
	#		1 - разрешено выполнение операции. Таймаут истек
	#		undef - таймаут не истек. Выполнение операции запрещено
	#	</p>
	sub addRecordToPays {
		my ($self,$mainAPI,$sid,$custid,$result,$tid,$paydate,$filname) = @_;

		# Инициализация переменных
		my ($sth) = ();
		my ($sec,$min,$hour,$currentmday,$currentmon,$currentyear,$wday,$yday,$isdst) = localtime(time);
		# Дата и время в разном формате
		my ($yearMonth,$yearMonth2) = ();
		
		if (!defined $paydate) {
			$currentmon = ($currentmon+1);
			$currentmday = sprintf "%02d",$currentmday;
			$currentmon = sprintf "%02d",$currentmon;
			$currentyear = $currentyear+1900;
			$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
			$yearMonth2 = $currentyear."-".$currentmon."-".$currentmday;
		} else {
			# выделить год и месяц
			$currentyear = substr($paydate,0,4);
			$currentmon = substr($paydate,5,2);
			$currentmday 	= substr($paydate,8,2);

			$currentmon = sprintf "%02d",$currentmon;
			$currentmday 	= sprintf "%02d",$currentmday;

			$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
			$yearMonth2 = $currentyear."-".$currentmon."-".$currentmday;
		}

		my %prevDate = $mainAPI->getPrevDateByMonth($currentyear,$currentmon,$currentmday);
		# Проверить на существование таблицу
		if (!defined $self->{tables}->{$yearMonth}) {
			$self->addPartition($mainAPI,$paydate);
		}

		if (defined $self->{tables}->{$yearMonth}) {
			my $query;
			if (defined $filname) {
				if (defined $paydate) {
					$query = "INSERT INTO logs.pays (sid,custid,result,paydate,tid,fil_name) VALUES (?,?,?,?,?,?);";
				} else {
					$query = "INSERT INTO logs.pays (sid,custid,result,paydate,tid,fil_name) VALUES (?,?,?,now(),?,?);";
				}
			} else {
				if (defined $paydate) {
					$query = "INSERT INTO logs.pays (sid,custid,result,paydate,tid) VALUES (?,?,?,?,?);";
				} else {
					$query = "INSERT INTO logs.pays (sid,custid,result,paydate,tid) VALUES (?,?,?,now(),?);";
				}
			}

			# Выполнить запрос
			unless ($sth = $mainAPI->{dbh}->prepare($query)) {
				$sth->finish();
				return undef;
			}

			if (defined $filname) {
				if (defined $paydate) {
					unless ($sth->execute($sid,$custid,$result,$paydate,$tid,$filname)) {
						$sth->finish();
						return undef;
					};
				} else {
					unless ($sth->execute($sid,$custid,$result,$tid,$filname)) {
						$sth->finish();
						return undef;
					};
				}
			} else {
				if (defined $paydate) {
					unless ($sth->execute($sid,$custid,$result,$paydate,$tid)) {
						$sth->finish();
						return undef;
					};
				} else {
					unless ($sth->execute($sid,$custid,$result,$tid)) {
						$sth->finish();
						return undef;
					};
				}
			}
			# Добавелние выполнено успешно
			return 1;
		} else {
			return 1;
		}
	}
1;