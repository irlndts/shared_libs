package SMPP2::Ext;
# Класс расширение для работы с протоколом smpp, на основе библиотеки SMPP2.
# Методы предназначены для автоматической обработки EnquireLInk, рекконекта соединения, обработка ответов отдельными классами хендлеров.

use strict;
use lib qw(/home/projects/SHARED_API/);
use SMPP2;
use Debug;
use Encode;

use base qw/SMPP2/;
$ENV{DEBUG} = 1;

=nd
Method: new
	Конструктор

Parameters:

Returns:

=cut

sub new {
	my $class = shift;
	my $this = {
		SMPP=>undef,
		WAIT_TRANS_PDU=>{ USSD=>{ enquire_link=>{}, submit_sm=>{} }, SMS=>{ enquire_link=>{}, submit_sm=>{} } },
		WAIT_MESS_PARTS=>{},
		smpp_check_time=>time(),
		conf=>{
			host=>undef,
			port=>2776,
			syslog=>sub{warn @_;},
			login=>undef,
			password=>undef,
			smpp_check_time=>5,
			type=>undef,
			@_
		},
	};
	bless $this,$class;
	return $this;
}

sub to_syslog {
	my $this = shift;
	my $msg = shift;		
	&{$this->{conf}{syslog}}($msg);
}

# Проверяет не пришло ли время для перепроверки сединения smpp
# Сперва наперво отсылает EnquireLink
sub smpp_check_connect {
	my $this = shift;
	# если коннекта и небыло никогда - создадим:
	return $this->smpp_connect() unless (defined $this->smpp());

	if ((time() - $this->{smpp_check_time}) > $this->{conf}{smpp_check_time}){
		# С момента последней активности по smpp прошло отведенное время
		if (%{$this->{WAIT_TRANS_PDU}{uc($this->{conf}{type})}{enquire_link}}){
			debug $this->{WAIT_TRANS_PDU}{uc($this->{conf}{type})}{enquire_link};
			# очерeди есть EnquireLink, значит уже посылали проверку EnquireLink. Делаем пересоединение с сервером.
			$this->{SMPP} = undef;
			return $this->smpp_connect();
		}else{
			debug "Stack EnquireLink is empty";
			$this->send_enquire_link();
			$this->reset_smpp_time();
		}
	}
	return $this->smpp();
}

# метод пересоединяется, вызывается если не обнаруживается никакой активности по имеющемуся соединению, или его и вовсе небыло.
sub smpp_connect {
	my $this = shift;
	$this->wait_trans_pdu_reinit();

	$this->reset_multipart_msg();
		
	$this->{SMPP} = SMPP2->new_connect($this->{conf}{host}, port=>$this->{conf}{port}, smpp_version =>0x34, async=>1, Blocking => 0) 
		or $this->to_syslog("Error connect to ".$this->{conf}{host}.":".$this->{conf}{port});
	unless ($this->{SMPP}){
		debug "undefined smpp before connect to server";
		return undef;
	}
	my $tr_seq = $this->smpp()->bind_transceiver(system_id=>$this->{conf}{login}, password=>$this->{conf}{password});
	$this->to_syslog("Send bind_transiever:".$tr_seq);
	return $this->smpp();
}

sub wait_trans_pdu_reinit {
	my $this = shift;
 	$this->{WAIT_TRANS_PDU} = { USSD=>{ enquire_link=>{}, submit_sm=>{} }, SMS=>{ enquire_link=>{}, submit_sm=>{} } }; 
}	

sub smpp {
	my $this = shift;
	return $this->{SMPP};
}

# сбрасываем время последней активности по smpp
sub reset_smpp_time {
	my $this = shift;
	$this->{smpp_check_time} = time();
}

# послать запрос на проверку соединения
sub send_enquire_link {
	my $this = shift;
	debug "Send EnquireLink";
	my $seq = $this->smpp()->enquire_link();
	unless ($seq){
		debug "Can't send Enquire enkuire link package.";
		$this->to_syslog("<$$> Can't send Enquirelink package.");
		return undef;
	}
	# так как enquirelink не сохраняем в транзакциях, присваиваем undef
	$this->{WAIT_TRANS_PDU}{uc($this->{conf}{type})}{enquire_link}{$seq} = undef;
	return 1;
}

# обработать полученный от smsc EnquireLink
sub handle_enquire_link {
	my $this = shift;
	# Получен пакет enquire link, отвечаем и обнуляем время проверки smpp соединения
	my $pdu = shift;
	$this->reset_smpp_time();
	return $this->smpp()->enquire_link_resp(seq =>$pdu->{seq});
}

# обработка ответа на посланный EnquireLink 
sub handle_enquire_link_resp {
	my $this = shift;
	my $pdu = shift;
	$this->reset_smpp_time();
	delete $this->{WAIT_TRANS_PDU}{uc($this->{conf}{type})}{enquire_link}{$pdu->{seq}};
}

# вернуть хеш значений seq <-> query_id которые ожидают респонза по пакету submit_sm
sub wait_submit_sm {
	my $this = shift;
	return $this->{WAIT_TRANS_PDU}{uc($this->{conf}{type})}{submit_sm};
}

# вернуть хеш значений seq <-> query_id которые ожидают респонза по пакету enquire_link 
sub wait_enquire_link {
	my $this = shift;	
	return $this->{WAIT_TRANS_PDU}{uc($this->{conf}{type})}{enquire_link};
}

# преобразовать строку в 16 ричный формат кодировки UCS2 
sub encode_str {
	my $this = shift;
	my $msg = shift;
	# выставляем флаг UTF если его нет.
	Encode::_utf8_on($msg) unless Encode::is_utf8($msg);

	# кодируем в UCS2
    return encode("UCS2",$msg);
}

# декодировать строку из 16 ричной кодировки UCS2 в UTF
sub decode_str {
	my $this = shift;
	my $msg = shift;
	debug "GET STR IN UCS2:",$msg;
	my $s = encode("UTF8",decode("UCS2",$msg));
	debug "ENCODEDE STR IN UTF8:",$s;
	debug "flag utf:".Encode::is_utf8($s);
	Encode::_utf8_on($s);
	debug "FLAG UTF UP:",$s;
	return $s;
}

# есть ли в строке многобайтные символы: возвращает undef - в случае одновайтной кодировки 1 - в случае многобайтной
sub is_mbyte_str {
	my $str = shift;
	return 1 unless $str =~ /^[\x00-\x7f]+$/;
	return undef;
}

=comment
Cобрать опции для отправкии сообщения, в зависимости от текста сообщения:
Проверяем нужно ли преобразовывать в UCS, преобразуем если надо
Возвращает ссылку на хеш параметров:
{ 
	short_message=>[MESSAGE]
	data_coding=>8, 
} - в случае многобайтного сообщения.

{
	short_message=>[MESSAGE]
} - в случае однобайтной.

# при передаче опционального параметра message_tlv - указываем в каком tlv параметре передавать сообщение:
short_message - по умолчанию, передается в случае короткого сообщения
message_payload - в случае составного сообщения 

=cut

# собрать опции для отправления пакета sms сообщения. По длине определяет через какой tlv параметр отсылать сообщение. Определяет в какой кодировке отправить.
sub compose_msg_opt_sms {
	my $this = shift;
	my $str = shift;

	my $l = length(Encode::encode_utf8($str));
	debug "compose_msg_opt_sms lenght:",$l;
	my $tlv_msg =  'short_message';
	if (is_mbyte_str($str)){
		# строка сотоит не только из однобайтных символов
		$tlv_msg='message_payload' if ($l > 254);
		return {$tlv_msg=>$this->encode_str($str), data_coding=>"8"};
	}

	# строка состоит только из однобайтовых символов, в декодировании не нуждается. Передача в message_payload, если длина сообщения более 255 байт
	$tlv_msg='message_payload' if ($l > 255);
	return {$tlv_msg=>$str};
}

# Собрать опции для отправки пакета ussd сообщения. Определяет первое ли это сообщение, исходя из этого проверяет ограничение на длину. 
# Если длина превышена - кричать об этом в сислог. Определяет в какой кодировке отправить сообщение.
sub compose_msg_opt_ussd {
	my $this = shift;
	my $str = shift;
	return {short_message=>$this->encode_str($str), data_coding=>"8"} if is_mbyte_str($str);
	return {short_message=>$str};
}

# прочитать сообщение с udh данными
=comment
Структура сбора мультисообщений такова:

WAIT_MESS_PARTS=>{
	[$origref]=>{
		parts=>{
			[$curpart]=>[$message_part]
		},
		maxparts=>[$maxparts],
		full_message=>''
	}
}
=cut
sub read_udh_message {
	my $this = shift;
	my $msg = shift;
	my $tmpl = "A6 A".(length($msg)-6);

	my ($u,$m) = unpack($tmpl,$msg);
	debug "BYTES UDH:",$u;
	debug "MEssage:",$m;

	# расшифровываем $udh:
	my @udh = map { ord($_) } (split //, $u);
	my ($origref,$maxparts,$curpart) = @udh[3..5];

	# проверяем приходили ли раньше другие части этого сообщения:
	if (exists $this->{WAIT_MESS_PARTS}{$origref}){
		# обнаружены данные с такимже origref
		my $WMP = $this->{WAIT_MESS_PARTS}{$origref};
		$WMP->{parts}{$curpart} = $m;
		
		# проверяем все ли части сообщения пришли.
		if ($WMP->{maxparts} ==  (scalar keys %{$WMP->{parts}}) ){
			# все необходимые части сообщения доступны - соединяем их:
			$WMP->{full_message} .= $WMP->{parts}{$_} for sort {$a <=> $b} keys %{$WMP->{parts}};
		}
	}else{
		# это первое сообщение из мультипартного сообщения, инициализируем ожидание:
		$this->{WAIT_MESS_PARTS}{$origref} = {
			parts=>{
				$curpart=>$m
			},
			maxparts=>$maxparts,
			full_message=>''
		}
	}

	# запоминаем пришедшую часть сообщения
	return (\@udh,$this->{WAIT_MESS_PARTS}{$origref}{full_message});
}

# Обнулить зарегистрированные составные сообщения:
sub reset_multipart_msg {
	my $this = shift;
	$this->{WAIT_MESS_PARTS} = {};
}


1;
