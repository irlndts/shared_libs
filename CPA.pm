#!/usr/bin/perl -w

# @tutorial Class фукнции для работы с интерфейсом CPA
# @version 0.2
# @copyright apiskun 25-27.06.2012
# @since
#	0.2.1
#		Добавлена функция getPlatformErrorDescriptionByCode и getSubscriptionStatusByCode
#		функции эктив и диэктив возвращают хеш, а не структуру
#	0.2
#		Добавлены функции CPAParseResponse, CPAServiceActive, CPAServiceDeactive
#	0.1.1
#		Добавление атрибута requestTimeout в CPACheck
#	0.1
#		Создание модуля
#		Создание функции CPACheck

package CPA;

BEGIN {
	use lib qw(/home/projects/SHARED_API);
	use sms;
}

use strict;
use LWP::UserAgent;
use utf8;
use Encode;
use Switch;


# Парсинг запроса CPA
# @param string response
#   <p>Строка, которая будет парситься</p>
# @return struct
#   <p>
#	$struct->{result} 
#	   1 - Строка обработана
#	   0 - 
#	  -1 - Отсутствуют тег (теги) типа запроса
#	  -2 - Тэги типа запроса в начале и конце не совпадают
#	  -3 - Аттрибуты отсутствуют
#	  -4 - Неправильные атрибуты 
#	$struct->{type}
#	  Тип запроса
#	$struct->{var attributes} 
#	  разнообразные аттрибуты из запроса, зависит от type:
#		expire_date
#		timestamp
#		msisdn
#		cause
#		serviceid
#   </p>

sub CPAParseResponse {
	my ($response) = shift;
	
	my $RESPONSE;

	#получаем тип запроса
	$response =~ m/^\<(\w+)\>.*\<\/(\w+)\>$/;
	
	if (!defined($1) or !defined($2)){
		print "Error: Wrong response line: There is no type tags\n";
		$RESPONSE->{result}=-1;
		return $RESPONSE;
		}

	unless (uc($1) eq uc($2)){
		print "Error: Wrong response line: Tags are wrong: $1 ne $2\n";
		$RESPONSE->{result}=-2;
		return $RESPONSE;
	}

	$RESPONSE->{type}=$1;

	#удаляем уже обработанное
	$response =~ s/^\<\w+\>//;
	$response =~ s/\<\/\w+\>$//;


	#Если приходить запрос getready
	if ($RESPONSE->{type} eq "getready"){
		$response =~ /^\<(\w+)\>/;
		my $subaction=$1;
		$RESPONSE->{getready}=$subaction;
		$response =~ s/^\<$subaction\>//;
		$response =~ s/\<\/$subaction\>//;
	}

	#обрабатываем каждый тег
	while ($response =~ s/^\<(\w+)\>(\w*)\<\/(\w+)\>//){
		
		if (!defined($1) or !defined($3)){
                	print "Error: Wrong attributes: There is no `tags\n";
                	$RESPONSE->{result}=-3;
                	return $RESPONSE;
                }
		
		unless (uc($1) eq uc($3)){
                	print "Error: Wrong attributes: Tags are wrong: $1 ne $3\n";
                	$RESPONSE->{result}=-4;
                	return $RESPONSE;
        	}
		
		$RESPONSE->{$1}=$2;
	}
	
	#Если в строке запроса ещё что-то осталось
	if (length($response)){
		print "Warning: Some attributes are missing: $response\n";
		$RESPONSE->{result}=-5;
		return $RESPONSE;
	}

	$RESPONSE->{result}=1;
	return $RESPONSE;

}




# Метод отключения услуги
# @param varchar(11) msisdn
#   <p>Номер телефона абонента</p>
# @param numstring serviceid
#   <p>Идентификатор сервиса CPA</p>
# @param string spaceurl
#   <p>хост CPA</p>
# @param int requestTimeout
#   <p>Необязательный атрибут для таймаута, по умолчанию 20 сек.
# @return hash
#   <p>
#   hash->{result}
#   	6 - Ошибка, подписка не удалась, см codeError
#   	1 - Подписка не удалась
#   	0 - Успешная подписка
# 	-1 - В ответе нет тега result
#  	-2 - неправильный номер msisdn
#  	-3 - запрос не прошел
#   hash->{codeError} в случае result 6
#		->{status} -код ошибки
#		->{description} - описание ошибки
#   </p>


sub CPAServiceDeactivate {
	my ($MSISDN,$ServiceID,$SpaceURL,$requestTimeout) = @_ ;
	my $RESPONSE;
	$requestTimeout = $requestTimeout || 20;

	unless (sms::is_good_msisdn($MSISDN)){
		print "Error: $MSISDN MSISDN is wrong\n";
		$RESPONSE->{result}=-2;
		return $RESPONSE;
	}

	#создание и подготовка юзер агента для отправления запросов к CPA
	my $ua = LWP::UserAgent->new;
	$ua->agent('SMSBot/1.01');
	$ua->timeout($requestTimeout);
	$ua->default_header('Accept-Language' => 'ru, en','Accept-Charset'  => 'utf-8;q=1, *;q=0.1');

	my $XML =<<XML;
<?xml version="1.0" encoding="UTF-8"?>
<deactivate>
<msisdn>$MSISDN</msisdn>
<serviceid>$ServiceID</serviceid>
</deactivate>
XML


	my $response = $ua->post($SpaceURL,
				Content_Type => 'text/xml;charset=us-ascii',
				Content => $XML
                		) or die "Error: can't post: $!";
	$ua = undef;
	

	# Ответ от CPA
	unless ($response->is_success) {
		printf "Error: Cannot get $MSISDN status from CPA $SpaceURL: %s\n", encode("cp1251",$response->status_line);
		$RESPONSE->{result}=-3;
		return $RESPONSE;
	}

	# Получить контент ответа
	my $content =  $response->content;
	
	#простой парсер построчно
	foreach (split "\n",$content){
		if (/^HTTP\/[\d\.]*\s*([\d]+)/) {
			if (defined $1) {
				my $errorCode=getPlatformErrorDescriptionByCode($1);
				$RESPONSE->{errorCode}=$errorCode;	
			}
		}
		if (/\<Status\>(\d+)\<\/Status\>/){
			$RESPONSE->{result}=$1;
			return $RESPONSE;
		}
	}
	printf "Error: There is no status line for $MSISDN in response from $SpaceURL: %s \n", encode("cp1251",$response->status_line);
	$RESPONSE->{result}=-1;
	return $RESPONSE;

}


# Метод подключения услуги
# @param varchar(11) msisdn
#   <p>Номер телефона абонента</p>
# @param numstring serviceid
#   <p>Идентификатор сервиса CPA</p>
# @param string spaceurl
#   <p>хост CPA</p>
# @param int requestTimeout
#   <p>Необязательный атрибут для таймаута, по умолчанию 20 сек.
# @return hash
#   <p>
#   hash->{result}
#   	6 - Ошибка, подписка не удалась, см. codeError
#   	1 - Подписка не удалась
#   	0 - Успешная подписка
# 	-1 - В ответе нет тега result
#  	-2 - неправильный номер msisdn
#  	-3 - запрос не прошел
#   hash->{codeError} в случае result 6
#		->{status} -код ошибки
#		->{description} - описание ошибки
#   </p>


sub CPAServiceActivate {
	my ($MSISDN,$ServiceID,$SpaceURL,$requestTimeout) = @_ ;
	my $RESPONSE;

	$requestTimeout = $requestTimeout || 20;

	unless (sms::is_good_msisdn($MSISDN)){
		print "Error: $MSISDN MSISDN is wrong\n";
		$RESPONSE->{result}=-2;
		return $RESPONSE;
	}

	#создание и подготовка юзер агента для отправления запросов к CPA
	my $ua = LWP::UserAgent->new;
	$ua->agent('SMSBot/1.01');
	$ua->timeout($requestTimeout);
	$ua->default_header('Accept-Language' => 'ru, en','Accept-Charset'  => 'utf-8;q=1, *;q=0.1');

	my $XML =<<XML;
<?xml version="1.0" encoding="UTF-8"?>
<activate>
<msisdn>$MSISDN</msisdn>
<serviceid>$ServiceID</serviceid>
</activate>
XML

	# отправить запрос в CPA

	my $response = $ua->post($SpaceURL,
				Content_Type => 'text/xml;charset=us-ascii',
				Content => $XML
                		) or die "Error: can't post: $!";
	$ua = undef;
	

	# Ответ от CPA
	unless ($response->is_success) {
		printf "Error: Cannot get $MSISDN status from CPA $SpaceURL: %s\n", encode("cp1251",$response->status_line);
		$RESPONSE->{result}=-3;
		return $RESPONSE;
	}

	# Получить контент ответа
	my $content =  $response->content;
	
	#простой парсер построчно
	foreach (split "\n",$content){
		if (/^HTTP\/[\d\.]*\s*([\d]+)/) {
			if (defined $1) {
				my $errorCode=getPlatformErrorDescriptionByCode($1);
				$RESPONSE->{errorCode}=$errorCode;	
			}
		}
		if (/\<Status\>(\d+)\<\/Status\>/){
			$RESPONSE->{result}=$1;
			return $RESPONSE;
		}
	}
	printf "Error: There is no status line for $MSISDN in response from $SpaceURL: %s \n", encode("cp1251",$response->status_line);
	$RESPONSE->{result}=-1;
	return $RESPONSE;

}


# Метод проверки статуса абонента
# @param varchar(11) msisdn
#   <p>Номер телефона абонента</p>
# @param numstring serviceid
#   <p>Идентификатор сервиса CPA</p>
# @param string spaceurl
#   <p>хост CPA</p>
# @param int requestTimeout
#   <p>Необязательный атрибут для таймаута, по умолчанию 20 сек.
# @return struct
#   <p>
#   $struct->{result}
#       1 - Подписка не найдена
#       0 - Подписка найдена
#      -1 - В ответе нет тега result
#      -2 - неправильный номер msisdn
#      -3 - запрос не прошел
#   $struct->{status}
#      субстатус подписки
#   $struct->{expire_date}
#      Дата окончания оплаченного периода
#   $struct->{status_line}
#      Информация об ошибке в случае -3
#   </p>

sub CPACheck{
	my ($MSISDN,$ServiceID,$SpaceURL,$requestTimeout) = @_;
	my $RESPONSE;

	#значение по умолчаниею
	$requestTimeout=$requestTimeout || 20;

	#проверка msisdn
	unless (sms::is_good_msisdn($MSISDN)){
		print "Error: $MSISDN MSISDN is wrong\n";
		$RESPONSE->{result} = -2;
		return $RESPONSE;
	}

	#создание и подготовка юзер агента для отправления запросов к CPA
	my $ua = LWP::UserAgent->new;
	$ua->agent('SMSBot/1.01');
	$ua->timeout($requestTimeout);
	$ua->default_header('Accept-Language' => 'ru, en','Accept-Charset'  => 'utf-8;q=1, *;q=0.1');

	my $XML =<<XML;
<?xml version="1.0" encoding="UTF-8"?>
<get_subscription_status>
<msisdn>$MSISDN</msisdn>
<serviceid>$ServiceID</serviceid>
</get_subscription_status>
XML


	# отправить запрос в CPA

	my $response = $ua->post($SpaceURL,
				Content_Type => 'text/xml;charset=us-ascii',
				Content => $XML
				);

	$ua = undef;

	# Ответ от CPA
	unless ($response->is_success) {
		print "Error: Cannot get $MSISDN status from CPA $SpaceURL: %s\n", encode("cp1251",$response->status_line);
		$RESPONSE->{result} = -3;
		$RESPONSE->{status_line} = $response->status_line;
		return $RESPONSE;
	}

	# Получить контент ответа
	my $content =  $response->content;

	#простой парсер построчно
	#=comment
	foreach (split "\n",$content){
		if (/\<result\>(\d+)\<\/result\>/){
			$RESPONSE->{result} = $1;
		}
		elsif (/\<Status\>(\d+)\<\/Status\>/){
			$RESPONSE->{status} = $1;
		}
		elsif (/\<expire_date\>(\d+)\<\/expire_date\>/){
			$RESPONSE->{expire_date} = $1;
		}
	}
	
	if(!defined $RESPONSE->{status} or $RESPONSE->{status} eq '0'){
		$RESPONSE->{status} = 0;
	}
	if(!defined $RESPONSE->{expire_date}){
		$RESPONSE->{expire_date} = 0;
	}
	if(!defined $RESPONSE->{result}) {
		$RESPONSE->{result} = -1;
	}
	
	if ($RESPONSE->{status}){
		getSubscriptionStatusByCode($RESPONSE->{status})?$RESPONSE->{result}=0:$RESPONSE->{result}=1;
	}

	
	
	return $RESPONSE;
	#=cut

	#MIME парсинг ответа
=comment
	my $parser = new MIME::Parser;

	$parser->output_dir("/tmp");
	$parser->output_prefix("checkSubs");
	$parser->output_to_core(1);

	my $MIME = "Content-Type: ".$response->header('Content-Type')."\n\n".$content;
	my $entity = $parser->parse_data($MIME);
	$parser->filer->purge;
	$parser = undef;

	if ($entity->mime_type() =~ /^multipart\/mixed/i) {
		#if($SpaceURL =~ /http:\/\/tocpa.vasmedia.ru\/([a-zA-Z_-]+)[\/]*/){
		#print $1." -> $MSISDN (MULTIPART)";
	#}else{
		#print $SpaceURL." -> $MSISDN (MULTIPART)";
	#}
	foreach my $subentity ($entity->parts()) {
		if ($subentity->mime_type() eq "text/xml") {
			# Получить result из xml
			foreach my $str (@{$subentity->body()}) {
				if ($str =~ /\<result\>(\d+)\<\/result\>/) {
					$RESPONSE->{result} = $1;
				}
				if ($str =~ /\<Status\>(\d+)\<\/Status\>/) {
					$RESPONSE->{status} = $1;
				}
				if ($str =~ /\<expire_date\>(\d+)\<\/expire_date\>/) {
					$RESPONSE->{expire_date} = $1;
				}
			}
			if(!defined $RESPONSE->{status}){
				$RESPONSE->{status} = 0;
			}
			if(!defined $RESPONSE->{expire_date}){
				$RESPONSE->{expire_date} = 0;
			}

			# Если есть result
			if (defined $RESPONSE->{result}) {
				$entity = undef;
				return $RESPONSE;
			} else {
				$RESPONSE->{result} = -1;
				$entity = undef;
				return $RESPONSE;
			}
		} else {
			$RESPONSE->{result} = -2;
			$entity = undef;
			return $RESPONSE;
		}
	}
	} else {
		$RESPONSE->{result} = -3;
		$entity = undef;
		return $RESPONSE;
    }
=cut
}


# Определяет причину ошибки по коду ошибки
# @param Integer errorCode
#	<p>Код ошибки</p>
# @return Hash
#	<p> 
#	[description] 		- Описание ошибки
#	[returnErrorStatus] - Статус ошибки, который необходимо вернуть
# 	</p>
sub getPlatformErrorDescriptionByCode {
	my ($errorCode) = shift;
	my $returnArray;
	switch($errorCode){
		case "1313"{
			$returnArray->{description} = "Рассылка несуществующей услуги";
			$returnArray->{status} = 402;
		}
		case "1314"{
			$returnArray->{description} = "Услуга не принадлежит Партнеру";
			$returnArray->{status} = 404;
		}
		case "1316"{
			$returnArray->{description} = "Рассылка с заблокированной услуги";
			$returnArray->{status} = 405;
		}
		case "1318"{
			$returnArray->{description} = "Регион местонахождения абонента заблокирован для данной услуги";
			$returnArray->{status} = 403;
		}
		case "1321"{
			$returnArray->{description} = "Регион местонахождения абонента неактивен";
			$returnArray->{status} = 403;
		}
		case "1325"{
			$returnArray->{description} = "Атрибут changeSubscribeLocation установлен некорректно";
			$returnArray->{status} = 405;
		}
		case "1326"{
			$returnArray->{description} = "Рассылка контента с некорректным типом трафика";
			$returnArray->{status} = 405;
		}
		case "1327"{
			$returnArray->{description} = "Регион абонента не найден";
			$returnArray->{status} = 402;
		}
		case "1332"{
			$returnArray->{description} = "Абонент не подписан";
			$returnArray->{status} = 170;
		}
		case "1333"{
			$returnArray->{description} = "Абонент заблокирован";
			$returnArray->{status} = 172;
		}
		case "1335"{
			$returnArray->{description} = "Услуга заблокирована для данного региона";
			$returnArray->{status} = 403;
		}
		case "1337"{
			$returnArray->{description} = "Запрос с некорректным типом трафика";
			$returnArray->{status} = 405;
		}
		case "1338"{
			$returnArray->{description} = "Подписка заблокирована";
			$returnArray->{status} = 403;
		}
		case "1340"{
			$returnArray->{description} = "Ошибка при работе с БД";
			$returnArray->{status} = 402;
		}
		case "1344"{
			$returnArray->{description} = "Выполнить операцию не удалось. Подписка заблокирована в Биллинге";
			$returnArray->{status} = 403;
		}
		case "1345"{
			$returnArray->{description} = "Системная ошибка";
			$returnArray->{status} = 402;
		}
		case "1346"{
			$returnArray->{description} = "Некорректная настройка услуги";
			$returnArray->{status} = 405;
		}
		case "1712"{
			$returnArray->{description} = "Абонент не отвечает в течение таймаута ожидания ответа на AoC";
			$returnArray->{status} = 402;
		}
		case "1713"{
			$returnArray->{description} = "Абонент отказался от предоставления услуги по AoC";
			$returnArray->{status} = 402;
		}
		case "1711"{
			$returnArray->{description} = "Не приходит отчет на AoC";
			$returnArray->{status} = 402;
		}
		case "1580"{
			$returnArray->{description} = "Абонент заблокирован (помещен в BlackList)";
			$returnArray->{status} = 180;
		}
		case "1714"{
			$returnArray->{description} = "AoC-сессия Абонента на услугу уже существует";
			$returnArray->{status} = 402;
		}
		case "1710"{
			$returnArray->{description} = "Не найдена страница с AoC";
			$returnArray->{status} = 402;
		}
		case "1376"{
			$returnArray->{description} = "Партнер отвечает на запрос по истечении MaxPushTimeout (ReplyTime для долгих транзакций)";
			$returnArray->{status} = 406;
		}
		case "1368"{
			$returnArray->{description} = "Партнер превысил максимально возможное число ответов";
			$returnArray->{status} = 402;
		}
		case "1336"{
			$returnArray->{description} = "Партнер отвечает на запрос для закрытой транзакции";
			$returnArray->{status} = 402;
		}
		case "1602"{
			$returnArray->{description} = "В первом контенте Партнер не присылает уровня цены или он некорректный (при управлении тарификацией Партнером)";
			$returnArray->{status} = 402;
		}
		case "1603"{
			$returnArray->{description} = "Произошла ошибка тарификации (списания). Например, не удается выгрузить CDR-запись (для PostPaid)";
			$returnArray->{status} = 402;
		}
		case "1537"{
			$returnArray->{description} = "Партнер отвечает на запрос с другого аккаунта, не принадлежащего Партнеру или некорректного для услуги";
			$returnArray->{status} = 402;
		}
		case "1346"{
			$returnArray->{description} = "Ответ партнера не зарегистрирован абонентом";
			$returnArray->{status} = 402;
		}
		case "1347"{
			$returnArray->{description} = "Абонент уже подписан на услугу";
			$returnArray->{status} = 172;
		}
		case "1348"{
			$returnArray->{description} = "Команда на отказ от подписки не выполнена. У вас не была оформлена данная подписка.";
			$returnArray->{status} = 170;
		}
		case "1339"{
			$returnArray->{description} = "Кастомизированный код ошибки в ситуации, когда провайдер пытается подписать абонента при отсутсвии соответствующего атрибута на услуге";
			$returnArray->{status} = 405;
		}
		case "1342"{
			$returnArray->{description} = "Абонент не подписан";
			$returnArray->{status} = 170;
		}
		case "1500"{
			$returnArray->{description} = "При запросе Партнером статуса (механизм «query_sm») MT-сообщение не найдено";
			$returnArray->{status} = 402;
		}
		case "1560"{
			$returnArray->{description} = "На контент Партнера ответ от SMSC не приходит, а генерируется mnCPA Router (с code равен «1»). Код передается на mnCPA Router (как subcode), чтобы партнеру уходил нужный команд статус";
			$returnArray->{status} = 402;
		}
		case "1800"{
			$returnArray->{description} = "Партнер прислал неверное сообщение в ответ на нотификацию";
			$returnArray->{status} = 402;
		}
		case "8"{
			$returnArray->{description} = "Код «по умолчанию», когда не найден код-настройка ошибки для отсылки Партнеру";
			$returnArray->{status} = 402;
		}
		case "88"{
			$returnArray->{description} = "Сообщение от партнера было отвергнуто по причине превышения производительности mnCPA Router или mnSMS Centre.";
			$returnArray->{status} = 502;
		}
		else {
			$returnArray->{description} = "Неизвестная ошибка платформы";
			$returnArray->{status} = 403;
		}
	}
	return $returnArray;
}


# Определяет статус подписки по коду status
# @author CQSpel
# @return
#	0 - disabled
#   1 - enabled
#	2 - suspended (Default)
#	-1 - подписка не обнаружена (в случае неверного региона)
	
sub getSubscriptionStatusByCode {
	my ($status) = shift;
	switch($status){
		case "101"{
			return 0;
		}
		case "106"{
			return 0;
		}
		case "107"{
			return 0;
		}
		case "108"{
			return 0;
		}
		case "124"{
			return 0;
		}
		case "125"{
			return 0;
		}
		case "201"{
			return 0;
		}
		case "210"{
			return 0;
		}
		case "211"{
			return 0;
		}
		case "212"{
			return 0;
		}
		case "222"{
			return 0;
		}
		case "223"{
			return 0;
		}
		case "224"{
			return 0;
		}
		case "230"{
			return 0;
		}
		case "231"{
			return 0;
		}
		
		case "100"{
			return 1;
		}
		case "102"{
			return 1;
		}
		case "104"{
			return 1;
		}
		case "105"{
			return 1;
		}
		case "110"{
			return 1;
		}
		case "111"{
			return 1;
		}
		case "120"{
			return 1;
		}
		case "121"{
			return 1;
		}
		case "122"{
			return 2;
		}
		case "123"{
			return 1;
		}
		case "126"{
			return 1;
		}
		case "200"{
			return 1;
		}
		case ("0"){
			return -1
		}
		else {return 2;}
	}
}

#
#my $start= time;
#for (1 .. 5000){
#my $response=CPACheck("79261154776","183801","http://tocpa.vasmedia.ru/moscow/");
#}
#my $end = time;
#print $end - $start;
#foreach my $tmpResp (keys %{$response}){
#	print "\t$tmpResp = ".$response->{$tmpResp}."\n";
#       }




=comment

print CPAServiceDeactivate("79261154776","177801","http://tocpa.vasmedia.ru/moscow/",5),"\n\n";
$response=CPACheck("79261154776","177801","http://tocpa.vasmedia.ru/moscow/");
foreach my $tmpResp (keys %{$response}){
		   print "\t$tmpResp = ".$response->{$tmpResp}."\n";
}


my $line = "<activate><msisdn>MSISDN</msisdn><serviceid>ServiceID</serviceid><cause>New</cause><expire_date>ExpireDate</expire_date><timestamp>TimeStamp</timestamp></activate>";

my $response = CPAParseResponse ($line);

foreach (keys %{$response}){
	print $_," => ",$response->{$_},"\n";
}



print "\n\n\n";
$line =  "<getready><action><msisdn>MSISDN</msisdn><serviceid>ServiceID</serviceid></action><cause>New</cause><expire_date>ExpireDate</expire_date><timestamp>TimeStamp</timestamp></getready>";


$response = CPAParseResponse ($line);

foreach (keys %{$response}){
	        print $_," => ",$response->{$_},"\n";
}

=cut


=comment
print "\n##########START############\n";
print "############CHECK NEW############\n";
my $response=CPACheck("79261154776","177800","http://tocpa.vasmedia.ru/moscow/");
foreach (keys %{$response}){
	   print "\t$_ = ".$response->{$_}."\n";
}

print "############CHECK############\n";
$response=CPACheck("79261154776","177801","http://tocpa.vasmedia.ru/moscow/");
foreach (keys %{$response}){
   print "\t$_ = ".$response->{$_}."\n";
}

print "\n\n#######ACTIVATE##########\n";
$response=CPAServiceActivate("79261154776","177801","http://tocpa.vasmedia.ru/moscow/",5);
foreach (keys %{$response}){
  	print "\t$_ = ".$response->{$_}."\n";
}


print "\n\n#########CHECK##########\n";
$response=CPACheck("79261154776","177801","http://tocpa.vasmedia.ru/moscow/");
foreach (keys %{$response}){
	   print "\t$_ = ".$response->{$_}."\n";
}




print "\n\n###########DEACTIVATE###########\n";
$response=CPAServiceDeactivate("79261154776","177801","http://tocpa.vasmedia.ru/moscow/",5);
foreach (keys %{$response}){
	  print "\t$_ = ".$response->{$_}."\n";
}



print "\n\n################CHECK###########\n";
$response=CPACheck("79261154776","177801","http://tocpa.vasmedia.ru/moscow/");
foreach (keys %{$response}){
          print "\t$_ = ".$response->{$_}."\n";
}

=cut

1;
