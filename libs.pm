package libs;

# Библиотека общеупотребимых функций

use POSIX;
use utf8;
use Encode;
use LWP;
use strict;
use Cache::Memcached;

# Определяет корректность формата msisdn
# @param text $msisdn
#        msisdn
# @return int
# 1 - правильный формат msisdn
# 0 - неверный формат msisdn
sub is_good_msisdn {
	my $msisdn = $_[0];

	if (length($msisdn) != 11) {
		return(0);
	} elsif ($msisdn !~ /^\d+$/) {
		return(0);
	};
	return(1);
};

# Определяет корректность формата email
# @param text $email
#        email
# @return int
# 1 - правильный формат email
# 0 - неверный формат email
sub is_good_email {
	my $email = $_[0];

	if ($email !~ /^.+@.+$/){
		return(0);
	};
	return(1);
};

# Перекодирует сообщение в формат пригодный для отправки через SMS
# @param text $istr
#	исходная строка для перекодирования
# @return text
#	перекодированная строка
sub UTF8toUCS2WWW {
	my ($istr) = @_;
	my $ostr;
	my @aistr = split(//,$istr);
	foreach my $ch (@aistr) {
		my $tstr = sprintf("%04X",ord($ch));
		if ($tstr =~ /^(\w{2})(\w{2})$/) {
			$ostr .= "%".$1."%".$2;
		}
	}
	return(encode("utf8", $ostr));
}

# Считывает конфигурационные файлы и формирует ссылку на хэш с параметрами из него
# @param text @files
#	список имен конфигурационных файлов (полный путь)
# @return hashref
#	ссылка на хэш с параметрами из всех указанных конфигурационных файлов
#	если в нескольких файлах есть одинаковые имена параметров, установится значение из последнего
sub parseConfig {
	my $cfg = {};

	my $cnt = 0;
	while (my $cfgfile = shift) {
		$cnt++;
		if ( -e $cfgfile ) {
			open(CFG, '<'.$cfgfile);
			while (<CFG>) {
				$_ =~ s/\#.*//gi;		# Удаляем комментарии
				$_ =~ s/^\s+//gi;		# Начальные пробелы
				$_ =~ s/\s+$//gi;		# Завершающие пробелы

				if ($_ =~ /^([a-zA-Z0-9\_]+)\=(.*)$/) {
					my $v = $2;
					my $ky = $1;
					$v =~ s/^\"//gi;
					$v =~ s/\"$//gi;
					$cfg->{$ky} = $v;
				} elsif ($_ =~ /^([a-zA-Z0-9\_]+)\[[\s]*\]\=(.*)$/) {
					my $v = $2;
					my $ky = $1;
					$v =~ s/^\"//gi;
					$v =~ s/\"$//gi;
					if (!defined $cfg->{$ky}) {$cfg->{$ky} = ();}
					$cfg->{$ky}->[@{$cfg->{$ky}}] = $v;
				};
			};
			close(CFG);

		} else {
			print STDERR "ERROR: Can not found config file: ", $cfgfile, "\n";
			exit;
		};
	};
	if ($cnt <= 0) {
		print STDERR "ERROR: Lost config file name\n";
		exit;
	};

	# Формируем массив memcached подключений из переменных типа memcNNN_host и memcNNN_port
	my $htmp = {};
	# Сформировать массив для рекламмы
	my $advert = {};
	foreach my $k (keys %{$cfg}) {
		if ($k =~ /^memc([0-9]+)\_host/) {
			$htmp->{$1}->{host} = $cfg->{$k};
		} elsif ($k =~ /^memc([0-9]+)\_port/) {
			$htmp->{$1}->{port} = $cfg->{$k};
		} elsif ($k =~ /^advert\_([0-9]+)\_([0-9A-Za-z\_\-\.]+)/) {
			$advert->{$1}->{$2} = $cfg->{$k};
		}
	};

	$cfg->{memc_servers} = ();
	my $sep = '';
	foreach my $k (sort(keys %{$htmp})) {
		push(@{$cfg->{memc_servers}}, $htmp->{$k}->{host}.':'.$htmp->{$k}->{port});
	};

	# Сформировать массив хешей
	$cfg->{advert} = ();
	foreach my $k (sort(keys %{$advert})) {
		my $tmp = {};
		foreach my $l (sort(keys %{$advert->{$k}})) {
			$tmp->{$l} = $advert->{$k}->{$l};
		}
		push(@{$cfg->{advert}}, $tmp);
	};

	return($cfg);
};

# Переводит скрипт в режим демона с перенаправлением вывода в указанный лог-файл
# @param text $log
#	полный путь к файлу лога. Если нет - вывод перенаправляется в /dev/null
# @param text $pidfile
#	полный путь к файлу pid
# @return нет
sub demonize {
        my ($log, $pidfile, $opt) = @_;

        fork_proc() && exit 0;

	my $skipsetuid = 0;
	if (defined($opt) && (ref($opt) eq '')) {
		$skipsetuid = $opt;
		undef($opt);
	};
	$opt = {} if (!defined($opt));

	open(FL, ">".$pidfile);
	print FL $$;
	close(FL);

	if (!defined($opt->{skip_setsid}) || ($opt->{skip_setsid} == 0)) {
		POSIX::setsid() or die "Can't set sid: $!";
	};

	if (!defined($opt->{skip_chdir}) || ($opt->{skip_chdir} == 0)) {
		$opt->{chdir} = '/' if (!defined($opt->{chdir}));
		chdir $opt->{chdir} or die "Can't chdir: $!";
	};

	if ((!defined($skipsetuid) || ($skipsetuid == 0)) && (!defined($opt->{skip_setuid}) || ($opt->{skip_setuid} == 0))) {
		POSIX::setuid(65534) or die "Can't set uid: $!";
	};

        $log = '/dev/null' if (!defined($log) || ($log eq ''));

	if (!defined($opt->{skip_std_redirect}) || ($opt->{skip_std_redirect} == 0)) {
        open(STDIN,  ">>".$log) or die "Can't open STDIN: $log $!";
		open(STDOUT, ">>".$log) or die "Can't open STDOUT: $!";
		open(STDERR, ">>".$log) or die "Can't open STDERR: $!";
	};
};

# Служебная процедура форка процесса для демонизации
# @param нет
# @return нет
sub fork_proc {
        my $pid;

        FORK: {
                if (defined($pid = fork)) {
                        return $pid;
                }
                elsif ($! =~ /No more process/) {
                        sleep 5;
                        redo FORK;
                }
                else {
                        die "Can't fork: $!";
                };
        };
};

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
# @return DBI
#	Если соединение в порядке, возвращает тот-же DBI, который был в параметре $dbh
#	Если соединение разорвано, формируется новый коннект и возвращается новый объект DBI
sub check_db_connect {
        my ($dbh, $dbhost, $dbport, $dbname, $dbuser, $dbpass, $repeattime) = @_;

        while (!defined($dbh) || !$dbh->ping()) {
		if (defined($dbh)) {
			print STDERR "check_db_connect: NO db connect... restore\n";
			print STDERR $dbh::errstr, "\n";
			$dbh->disconnect;
			undef($dbh);
		};
                $dbh = DBI->connect("dbi:Pg:host=".$dbhost.";port=".$dbport.";dbname=".$dbname, $dbuser, $dbpass, {AutoCommit => 0, RaiseError => 0, PrintError => 0});

                if (!defined($dbh) || !$dbh->ping()) {
			print STDERR "check_db_connect: can not restore db connect:\n";
			print STDERR $dbh::errstr, "\n";
			if (defined($repeattime) && ($repeattime > 0)) {
				sleep($repeattime);
			} else {
				die "Can not connect to database: ".$dbhost.":".$dbport." ".$dbname.": \n".$dbh::errstr;
			};
                };

                if ((!defined($dbh) || !$dbh->ping()) && (!defined($repeattime) || ($repeattime eq ''))) {
			undef($dbh);
			last;
                };
        };
        return($dbh);
}

# Процедура контроля соединения к серверу memcached
# @param Cache::Memcached $memc
#	коннект к серверу memcached
# @param text $servers
#	сервер для подключения в виде "ip:port"
# @param text $namespace
#	пространстов имен
# @return DBI
#	Если соединение в порядке, возвращает тот-же Cache::Memcached, который был в параметре $memc
#	Если соединение разорвано, формируется новый коннект и возвращается новый объект Cache::Memcached
#	Если соединение не было установлено - возвращается undef
sub check_memc_connect {
	my ($memc, $servers, $namespace) = @_;
	my $flg;
	if (defined($memc)) {
		$memc->set('test_flag', 1);
		$flg = $memc->get('test_flag');
	};
	if (!defined($flg) || ($flg eq '')) {
		if (defined($servers)) {
			if (ref($servers) eq 'ARRAY') {
				$memc = Cache::Memcached->new( { 'servers' => $servers,
						'namespace' => $namespace,
						'compress_threshold' => 1000, } );
			} else {
				$memc = Cache::Memcached->new( { 'servers' => [ $servers ],
						'namespace' => $namespace,
						'compress_threshold' => 1000, } );
				open(FL, '>>/var/log/projects/memcache.log');
				print FL "WARNING: Use old style memcached config: ", $0, "\n";
				close(FL);
			};
			# Проверка подключения к серверу(ам) memecached
			$memc->set('testval', 123);
			my $testvalmemc = $memc->get('testval');
			if ((!defined $testvalmemc) ||(123 ne $testvalmemc)){
				return undef;
			};
		};
	};
	return($memc);
};

# Процедура проверки доступа по IP адресу и списку разрешенных IP адресов (с подсетями типа /24, /16 или /8)
# @param text $iplist
#	список разрешенных IP через запятую
# @param text $ip
#	проверяемый IP
# @return int
#	1 - если доступ разрешен
#	0 - если доступ запрещен
sub check_ip_access {
	my ($iplist, $ip, $option1) = @_;

	my @ipl = split(/\,/, $iplist);

	my $access = 0;
	foreach my $ipr (@ipl) {
		if ($ipr =~ /^([^\|]+)\|(.+)$/) {
			if ($1 eq $ip) {
				my @options = split(/\|/, $2);
				if (defined($options[0])) {
					if ($options[0] eq $option1) {
						return(1);
					};
				}; 
			};
		} elsif ($ipr =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)\/(\d+)$/) {
# Подсеть       
			my $l = int($5/8);
			my @ipa = split(/\./, $ip);
			my @net = map (dec2bin($_),($1, $2, $3, $4));
			@ipa = map (dec2bin($_), @ipa);

			my $ipabin = join('',@ipa);
			my $netbin = join('',@net);

			print substr($ipabin&mask2bin($5),0,$5),"\n";
			print substr($netbin,0,$5),"\n";

			if ( substr($ipabin&mask2bin($5),0,$5) eq substr($netbin,0,$5)){
				return 1;
			}
			else {
				return 0;       
			};      
		} else {
			return(1) if ((defined $ip) && ($ipr eq $ip));
		};              
	};
	return(0);
};


sub dec2bin {
	my $str = unpack("B32", pack("N", shift));
	my @arr = split('',$str);
	return splice(@arr,-8);
}

sub mask2bin {
	my $mask = shift;
	return '1' x $mask.'0'x(32-$mask);

}

# Формирует из кирилицы текст транслитом латинскими буквами
# @param text $text
#	исходный текст
# @return text
#	возвращает текст транслитом соответствующих исходному
sub translit
{
    my $text = shift;
    $text = decode('utf8', $text);

    $text =~ y/ абвгдеёзийклмнопрстуфхъыьэ/_abvgdeezijklmnoprstufh'y'e/;
    $text =~ y/АБВГДЕЁЗИЙКЛМНОПРСТУФХЪЫЬЭ/ABVGDEEZIJKLMNOPRSTUFH'Y'E/;
    my %mchars = ('ж'=>'zh','ц'=>'tz','ч'=>'ch','ш'=>'sh','щ'=>'sch','ю'=>'ju','я'=>'ja',
                  'Ж'=>'ZH','Ц'=>'TZ','Ч'=>'CH','Ш'=>'SH','Щ'=>'SCH','Ю'=>'JU','Я'=>'JA');

    map {$text =~ s/$_/$mchars{$_}/g} (keys %mchars);

    return $text;
}

sub check_for_one_instance {
	my $cfg = $_[0];

	if ($< ne '0') {
		print STDERR "ERROR: Application possible running only under root user\n";
		exit();
	};

	open(LOCK, '>'.$cfg->{lock_file});
	flock(LOCK, 2);
	if ( -e $cfg->{pid_file} ) {
		open(FL, '<'.$cfg->{pid_file});
		my $pid = <FL>;
		close(FL);

		my $cmd = "/bin/ps -A|grep -E \"^[^0-9]*".$pid."\"|awk '{print \$1}'";
		
		my $pidstr = `$cmd`;
		chomp($pidstr);

		if ($pid eq $pidstr) {
			print STDERR "ERROR: Application already running (pid:", $pid, ")\n";
			exit();
		} else {
			open(FL, '>'.$cfg->{pid_file});
			print FL $$;
			close(FL);
		};
	};
	close(LOCK);
};

# Отправить смс через каннел
# @param integer $msisdn
#	<p>
#		Номер телефона абонента
#	</p>
# @param String $serviceNumber
#	<p>
#		Сервисный номер
#	</p>
# @param String $message
#	<p>
#		Соообщение, которое необходимо отправить
#	</p>
# @param Bit $dlr_mask
#	<p>
#		флаг настройки отчета о доставке
#		1	- доставлено на телефон абонента
#		2	- не доставлено на телефон абонента
#		4	- поставлено в очередь доставки на CMSC
#		8	- доставлено на SMSC
#		16	- не доставлено на SMSC
#		31	- все сразу
#	</p>
# @param String $clevel
#	<p>
#		Тарифный класс для mt
#	</p>
# @param String $dlr_url
#	<p>
#		URL, на которы йнеобходимо отправить отчет о доставке
#	</p>
# @param Integer $timeout
#	<p>
#		Таймаут ответа от каннела
#	</p>
# @param Integer $smsboxu
#	<p>
#		Имя пользователя smsbox (разделяет коннекты от каннела к SMSC)
#	</p>
# @param Integer $smsboxpw
#	<p>
#		Пароль пользователя smsboxpw
#	</p>
# @param String $url
#	<p>
#		URL сайта с каннел
#	</p>
# @return
#	<p>
#		undef - не удалось отправить сообщение
#		1 - сообщение отправлено
#	</p>
sub smsSendKannel {
	my ($msisdn,$serviceNumber,$message,$dlr_mask,$clevel,$dlr_url,$timeout,$smsboxu,$smsboxpw,$url) = @_;
	unless(utf8::is_utf8($message)) {
		$message = decode('utf8',$message);
	}

	$url = 'http://192.168.168.32:13013/cgi-bin/sendsms' if (!defined($url));

	my $ua = LWP::UserAgent->new;
	if (!defined $timeout) {
		$ua->timeout(5);
	} else {
		$timeout = int($timeout);
		$ua->timeout($timeout);
	}

	my $mbk = "smpp_kannel";
	if (!defined $smsboxu) {
		$smsboxu = 'tester';
	}
	if (!defined $smsboxpw) {
		$smsboxpw = 'foobar';
	}
	unless (defined $dlr_mask) {
		$dlr_mask = 31;
	}
	unless (defined $dlr_url) {
		$dlr_url = 'http://192.168.168.32/mt/fprocdlr.fpl?id=%25F%26status=%25d%26send_time=%25t%26from=%25P%26to=%25p';
	}
	if (defined $clevel) {
		$dlr_url .= "%26charge=$clevel";
	}

	my $getr = "http://192.168.168.32:13013/cgi-bin/sendsms?username=$smsboxu&password=$smsboxpw&from=$serviceNumber&to=$msisdn&coding=2";
	my $flagOK = 1;
	# Разбить смс на части по 60 символов
	if (length($message) > 60) {
		my $mid = sprintf("%02X",int(rand(255)));
		my @parts=split(/([\w\d\s\S]{60})/,$message);

		for (my $i=0;$i<=$#parts;$i++) {
			$getr = $url."?username=$smsboxu&password=$smsboxpw&from=$serviceNumber&to=$msisdn&coding=2";
			my $udh = "%05%00%03%".$mid."%".sprintf("%02X",$#parts+1)."%".sprintf("%02X",$i+1);
			$getr .= "&udh=$udh";
			if (defined $parts[$i]) {
				my $textTMP = UTF8toUCS2WWW($parts[$i]);
				if (defined $textTMP) {
					$getr .= "&text=".UTF8toUCS2WWW($parts[$i]);
				}
			}
			if ($i == $#parts) {
				$getr .= "&dlr-mask=$dlr_mask&dlr-url=$dlr_url";
				if (defined $clevel) {
					$getr .= "&meta-data=%3Fsmpp%3Fchargebercut%3D".$clevel;
				}
			}
			my $response = $ua->get($getr);
			$flagOK = undef unless ((defined $flagOK)&&($response->is_success)&&($response->content =~ /(\d+):\s(\w+)/));
		}
		$ua = undef;
	} else {
		if (defined $clevel) {
			$getr .= "&meta-data=%3Fsmpp%3Fchargebercut%3D".$clevel;
		}
		$getr .= "&text=".UTF8toUCS2WWW($message);
		$getr .= "&dlr-mask=$dlr_mask&dlr-url=$dlr_url";
		my $response = $ua->get($getr);
		$ua = undef;
		if ($response->is_success) {
			if ($response->content =~ /(\d+):\s(\w+)/) {
				$flagOK = 1;
			} else {
				$flagOK = undef;
			}
		} else {
			$flagOK = undef;
		}
	}
	if (defined $flagOK) {
		return 1;
	}
	return undef;
};

# Не отправляет смс, а выдает в виде массива список урл для отправки смс (для использования в асинхронном режиме)
sub smsSendKannelRequests {
	my ($msisdn,$serviceNumber,$message,$dlr_mask,$clevel,$dlr_url,$timeout,$smsboxu,$smsboxpw,$url) = @_;
	my @result;
	unless(utf8::is_utf8($message)) {
		$message = decode('utf8',$message);
	}

	$url = 'http://192.168.168.32:13013/cgi-bin/sendsms' if (!defined($url));

	my $mbk = "smpp_kannel";
	if (!defined $smsboxu) {
		$smsboxu = 'tester';
	}
	if (!defined $smsboxpw) {
		$smsboxpw = 'foobar';
	}
	unless (defined $dlr_mask) {
		$dlr_mask = 31;
	}
	unless (defined $dlr_url) {
		$dlr_url = 'http://192.168.168.32/mt/fprocdlr.fpl?id=%25F%26status=%25d%26send_time=%25t%26from=%25P%26to=%25p';
	}
	if (defined $clevel) {
		$dlr_url .= "%26charge=$clevel";
	}

	my $getr = "http://192.168.168.32:13013/cgi-bin/sendsms?username=$smsboxu&password=$smsboxpw&from=$serviceNumber&to=$msisdn&coding=2";
	my $flagOK = 1;
	# Разбить смс на части по 60 символов
	if (length($message) > 60) {
		my $mid = sprintf("%02X",int(rand(255)));
		my @parts=split(/([\w\d\s\S]{60})/,$message);

		for (my $i=0;$i<=$#parts;$i++) {
			$getr = $url."?username=$smsboxu&password=$smsboxpw&from=$serviceNumber&to=$msisdn&coding=2";
			my $udh = "%05%00%03%".$mid."%".sprintf("%02X",$#parts+1)."%".sprintf("%02X",$i+1);
			$getr .= "&udh=$udh";
			if (defined $parts[$i]) {
				my $textTMP = UTF8toUCS2WWW($parts[$i]);
				if (defined $textTMP) {
					$getr .= "&text=".UTF8toUCS2WWW($parts[$i]);
				}
			}
			if ($i == $#parts) {
				$getr .= "&dlr-mask=$dlr_mask&dlr-url=$dlr_url";
				if (defined $clevel) {
					$getr .= "&meta-data=%3Fsmpp%3Fchargebercut%3D".$clevel;
				}
			}
			push(@result, $getr);
		}
	} else {
		if (defined $clevel) {
			$getr .= "&meta-data=%3Fsmpp%3Fchargebercut%3D".$clevel;
		}
		$getr .= "&text=".UTF8toUCS2WWW($message);
		$getr .= "&dlr-mask=$dlr_mask&dlr-url=$dlr_url";
		push(@result, $getr);
	}
	return \@result;
};

sub postgres_time_to_unix {
	my ($ptime) = @_;

	my $utime;
	if ($ptime =~ /^(\d{4})\-(\d{2})\-(\d{2}) (\d{2}):(\d{2}):(\d{2}).*$/) {
		$utime = mktime($6, $5, $4, $3, $2-1, $1-1900, 0, 0);
	};
	return($utime);
};

sub unix_time_to_postgres {
	my ($utime) = @_;

	return(strftime('%Y-%m-%d %H:%M:%S', localtime($utime)));
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

1;
