#!/usr/bin/perl -w

# @copyright CQSpel 2011
# Class
# 	Работа с хранилищем отправленных sms (обновление статуса в течение 1 суток)
package SendSMPPAPI;

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
		my $proto = shift;
		my $class = ref($proto) || $proto;
		my $count++;
		my $self = {};
		$self->{tables} 	= {};

		# Массив ошибок (для отладки)
		$self->{errors} 	= {};

		# инициализация ссылки на класс (объект)
		bless ($self,$class);
	}

	sub DESTROY {
		my $self = shift;
		$count--;
	}

	# Получает список патиций
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
	WHERE tablename like 'send_smpp_comm_%'
	ORDER BY tablename
";
				# Выполнить запрос
				unless ($sth = $mainAPI->{dbh}->prepare($query)) {
					$self->{errors}->{DBI} = "Не удалось подготовить запрос на определение списка таблиц";
					$sth->finish();
					return undef;
				}

				unless ($sth->execute()) {
						$self->{errors}->{DBI} = "Не удалось выполнить запрос на извлечение списка активных таблиц";
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

	# Добавляет патиционную таблицу в базу (физически)
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
			my $query = "SELECT sms.checkcreate_send_smpp_comm_tablename(?);";
			# Выполнить запрос
			unless ($sth = $mainAPI->{dbh}->prepare($query)) {
				$self->{errors}->{DBI} = "Не удалось подготовить запрос на добавление таблицы";
				$sth->finish();
				return undef;
			}
			unless ($sth->execute($yearMonth)) {
					$self->{errors}->{DBI} =  "Не удалось выполнить запрос на добавление таблицы";
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

	# Удаляет физически таблицу
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
			my $query = "DROP TABLE IF EXISTS sms.send_smpp_comm_".$yearMonth.";";
			# Выполнить запрос
			unless ($sth = $mainAPI->{dbh}->prepare($query)) {
				$self->{errors}->{DBI} = "Не удалось подготовить запрос на удаление патиции таблицы";
				$sth->finish();
				return undef;
			}
			unless ($sth->execute()) {
					$self->{errors}->{DBI} = "Не удалось выполнить запрос на удаление патиции таблицы";
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

	# Добавляет запись в таблицу
	# @param MainAPI $mainAPI
	#	<p>Экземпляр класса основных функций</p>
	# @param bigint $msisdn
	#	<p>Номер телефона абонента</p>
	# @param bigint $sn
	#	<p>Идентификатор подписки</p>
	# @param bigint $sms
	#	<p>Текст смс</p>
	# @param bigint $opid
	#	<p>Идентификатор оператора</p>
	# @param bigint $opifaceid
	#	<p>идентификатор интерфейса</p>
	# @param bigint $sendtime
	#	<p>Дата и время отправки смс</p>
	# @return
	#	<p>
	#		1 - разрешено выполнение операции. Таймаут истек
	#		undef - таймаут не истек. Выполнение операции запрещено
	#	</p>
	sub addRecordToSendSMPP {
		my ($self,$mainAPI,$msisdn,$sn,$sms,$opid,$opifaceid,$sendtime) = @_;

		# Инициализация переменных
		my ($sth) = ();
		my ($sec,$min,$hour,$currentmday,$currentmon,$currentyear,$wday,$yday,$isdst) = localtime(time);
		# Дата и время в разном формате
		my ($yearMonth,$yearMonth2) = ();

		if (!defined $sendtime) {
			$currentmon = ($currentmon+1);
			$currentmday = sprintf "%02d",$currentmday;
			$currentmon = sprintf "%02d",$currentmon;
			$currentyear = $currentyear+1900;
			$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
			$yearMonth2 = $currentyear."-".$currentmon."-".$currentmday;
		} else {
			# выделить год и месяц
			$currentyear 	= substr($sendtime,0,4);
			$currentmon 	= substr($sendtime,5,2);
			$currentmday 	= substr($sendtime,8,2);

			$currentmon = sprintf "%02d",$currentmon;
			$currentmday 	= sprintf "%02d",$currentmday;

			$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
			$yearMonth2 = $currentyear."-".$currentmon."-".$currentmday;
		}

		my %prevDate = $mainAPI->getPrevDateByMonth($currentyear,$currentmon,$currentmday);
		# Проверить на существование таблицу
		if (!defined $self->{tables}->{$yearMonth}) {
			$self->addPartition($mainAPI,$sendtime);
		}

		if (defined $self->{tables}->{$yearMonth}) {
			my $query;
			if (defined $sendtime) {
				$query = "INSERT INTO sms.send_smpp_comm (msisdn,sn,sms,opid,opifaceid,sendtime) values (?,?,?,?,?,?);";
			} else {
				$query = "INSERT INTO sms.send_smpp_comm (msisdn,sn,sms,opid,opifaceid,sendtime) values (?,?,?,?,?,now())";
			}

			# Выполнить запрос
			unless ($sth = $mainAPI->{dbh}->prepare($query)) {
				$sth->finish();
				return undef;
			}

			if (defined $sendtime) {
				unless ($sth->execute($msisdn,$sn,$sms,$opid,$opifaceid,$sendtime)) {
					$sth->finish();
					return undef;
				};
			} else {
				unless ($sth->execute($msisdn,$sn,$sms,$opid,$opifaceid)) {
					$sth->finish();
					return undef;
				};
			}

			# Добавелние выполнено успешно
			return 1;
		} else {
			return 0;
		}
	}

	# Обновляет запись в таблице
	# @param MainAPI $mainAPI
	#	<p>Экземпляр класса основных функций</p>
	# @param bigint $answer_time
	#	<p>Дата и время ответа</p>
	# @param bigint $cpa_cmd_type
	#	<p>Тип</p>
	# @param bigint $id
	#	<p>Идентификатор записи в базе</p>
	# @return
	#	<p>
	#		1 - разрешено выполнение операции. Таймаут истек
	#		undef - таймаут не истек. Выполнение операции запрещено
	#	</p>
	sub updateRecordInSendSMPP {
		my ($self,$mainAPI,$cpa_cmd_type,$id) = @_;

		# Инициализация переменных
		my ($sth) = ();
		my ($sec,$min,$hour,$currentmday,$currentmon,$currentyear,$wday,$yday,$isdst) = localtime(time);
		# Дата и время в разном формате
		my ($yearMonth,$yearMonth2) = ();

		$currentmon = ($currentmon+1);
		$currentmday = sprintf "%02d",$currentmday;
		$currentmon = sprintf "%02d",$currentmon;
		$currentyear = $currentyear+1900;
		$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
		$yearMonth2 = $currentyear."-".$currentmon."-".$currentmday;

		my %prevDate = $mainAPI->getPrevDateByMonth($currentyear,$currentmon,$currentmday);

		my $query;
		$query = "UPDATE sms.send_smpp_comm SET answer_time = now(), cpa_cmd_type = ? WHERE id = ? AND ((date(sendtime) = '".$yearMonth2."'::date) OR (date(sendtime) = '".$prevDate{prev}{year}."-".$prevDate{prev}{month}."-".$prevDate{prev}{day}."'::date));";
		# Выполнить запрос
		unless ($sth = $mainAPI->{dbh}->prepare($query)) {
			$sth->finish();
			return undef;
		}
		unless ($sth->execute($cpa_cmd_type,$id)) {
			$sth->finish();
			return undef;
		};
		# Добавелние выполнено успешно
		return 1;
	}

	# Выбирает идентификаторы из таблицы
	# @param MainAPI $mainAPI
	#	<p>Экземпляр класса основных функций</p>
	# @param bigint $msisdn
	#	<p>Номер телефона абонента</p>
	# @return
	#	<p>
	#		1 - разрешено выполнение операции. Таймаут истек
	#		undef - таймаут не истек. Выполнение операции запрещено
	#	</p>
	sub selectLStRecords {
		my ($self,$mainAPI,$msisdn) = @_;

		# Инициализация переменных
		my ($sth) = ();
		my ($sec,$min,$hour,$currentmday,$currentmon,$currentyear,$wday,$yday,$isdst) = localtime(time);
		# Дата и время в разном формате
		my ($yearMonth,$yearMonth2) = ();

		$currentmon = ($currentmon+1);
		$currentmday = sprintf "%02d",$currentmday;
		$currentmon = sprintf "%02d",$currentmon;
		$currentyear = $currentyear+1900;
		$yearMonth = $currentyear."_".$currentmon."_".$currentmday;
		$yearMonth2 = $currentyear."-".$currentmon."-".$currentmday;

		my %prevDate = $mainAPI->getPrevDateByMonth($currentyear,$currentmon,$currentmday);

		if (defined $msisdn) {
			my $query;
			$query = "SELECT sms.fns_ssc_for_msisdn('".$msisdn."','".$yearMonth2."','".$prevDate{prev}{year}."-".$prevDate{prev}{month}."-".$prevDate{prev}{day}."') as id;";
			# Выполнить запрос
			unless ($sth = $mainAPI->{dbh}->prepare($query)) {
				$sth->finish();
				return undef;
			}
			unless ($sth->execute()) {
				$sth->finish();
				return undef;
			}
			if ($sth->rows() > 0) {
				my $id = $sth->fetchrow_array();
				if (defined $id) {
					return $id->{id};
				}
			} else {
				return undef;
			}
		} else {
			return undef;
		}
		# Добавелние выполнено успешно
		return undef;
	}
1;