package sms;

# Библиотека функций для работы с sms и msisdn

# is_good_msisdn 		- определяет соответствует-ли msisdn правильному его представлению
# UTF8toUCS2WWW 		- перекодирует сообщение в формат пригодный для отправки через SMS
# translit 			- формирует из кирилицы текст транслитом латинскими буквами
# smsSendKannel 		- отправить смс через каннел
# smsSendKannelRequests		- не отправляет смс, а выдает в виде массива список урл для отправки смс (для использования в асинхронном режиме)

use strict;
use POSIX;
use utf8;
use Encode;
use LWP;
use Switch;

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
		@parts = grep {$_} @parts;

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
		@parts = grep {$_} @parts;

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

# Простая функция отправки смс без лишних параметров
sub send_sms {
	my ($from, $to, $msg) = @_;
	
	smsSendKannel($to,$from,$msg,undef,undef,undef,undef,undef,undef);
};

sub send_sms_requests {
	my ($from, $to, $msg) = @_;
	return(smsSendKannelRequests($to,$from,$msg,undef,undef,undef,undef,undef,undef));
};

# Отправляет смс через мобиконт по http интерфейсу (ограничен по количеству запросов в сек)
# @params String $mbkHost
#	- ip адрес серверка Mobicont через который выполнить отправку смс
# @params String $method
#	- Метод отправки mt,mo
# @params String $msisnd
#	- Номер телефона абонента в формате 7хххууууууу
# @params String $sn
#	- Сервисный номер, на который, с которого выполнить отпраку
# @params String $message
#	- сообщение смс
# @params Hash $config
#	- хеш с конфигурационными параметрами
# @return
#	- 1 or undef
sub sendMobicont {
	my ($mbkHost, $method, $msisdn, $sn, $message, $config,$timeout) = @_;
	if (!defined $msisdn) {return undef;}
	if (!defined $message) {return undef;}
	$sn = 'SMS_INFO' if (!defined $sn);
	$mbkHost = '192.168.168.18' if (!defined $mbkHost);
	$method = 'mt' if (!defined $method);
	$timeout = 20 if (!defined $timeout);

	switch ($method) {
		case "mo" {
			unless(utf8::is_utf8($message)) {
				sys::toSyslog('Not utf-8') if ($config->{debug} eq 1);
				$message = decode("utf8",$message);
			}
			my $url = "http://$mbkHost:9002/social_mo?sn=$sn&msisdn=$msisdn&text=".$message;
			my $uri = URI::Encode->new({encode_reserved =>0});
			$url = $uri->encode($url);
			$uri = undef;
			sys::toSyslog($url,1) if ($config->{debug} eq 1);
			my $ua = LWP::UserAgent->new;
			$ua->timeout($timeout);
			my $response = $ua->get($url);
			my $content = $response->content;
			$ua = undef;
			# @todo считать количество ошибок по недоставке
			if (!$response->is_success){
				sys::toSyslog("BAD Answer",undef,'alert','error');
				return undef;
			}
		}
		case "mt" {
			unless(utf8::is_utf8($message)) {
				sys::toSyslog('Not utf-8') if ($config->{debug} eq 1);
				$message = decode("utf8",$message);
			}
			my $url = "http://$mbkHost:9002/social_mt?sn=$sn&msisdn=$msisdn&text=".$message;
			my $uri = URI::Encode->new({encode_reserved =>0});
			$url = $uri->encode($url);
			$uri = undef;
			sys::toSyslog($url,1) if ($config->{debug} eq 1);
			my $ua = LWP::UserAgent->new;
			$ua->timeout($timeout);
			my $response = $ua->get($url);
			my $content = $response->content;
			$ua = undef;
			# @todo считать количество ошибок по недоставке
			if (!$response->is_success){
				sys::toSyslog("BAD Answer",undef,'alert','error');
				return undef;
			}
		} else {
			return undef;
		}
	}
	return 1;
}

1;
