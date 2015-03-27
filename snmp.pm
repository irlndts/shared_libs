package SNMP_INTF;

use strict;
use warnings;
use Net::SNMP;
use Switch;

my ($OIDS_LOG_FILE_PATH, $APP_NAME, $OIDS_LOG_FILE_NAME, $OIDS_LOG_HASH);

# Конструктор  
sub new {
	my ($type, $cfg, $oid_settings);
	($type, $cfg, %$oid_settings) = @_;
	my $service = $oid_settings->{service_name};
	my $application = $oid_settings->{app_name};
	my $thread = $oid_settings->{thread_no};
	
	my $self = {};

	$OIDS_LOG_FILE_PATH = "/tmp/snmp";
	$APP_NAME = $oid_settings->{project_name} || "";
	$self->{application_name} = $0;
	if ($0 =~ /\/([\w_]+)\.*\w*$/) { 
		$APP_NAME = $1;
	}

	# список фактически созданных OID`ов будем хранить тут
	$OIDS_LOG_FILE_NAME = $OIDS_LOG_FILE_PATH."/".$APP_NAME."_oids.log";
	$OIDS_LOG_HASH = {};
	
	# создадим, если не существует, каталог для записи списка создаваемых переменных
	if (rmkdir($OIDS_LOG_FILE_PATH)) {
		# прочитаем то, что там есть
		&read_oids_from_log($OIDS_LOG_FILE_NAME, $OIDS_LOG_HASH);
	};
	
	# параметры подключения к snmpd
	my $hostname 	= defined $oid_settings->{snmp_hostname} ? $oid_settings->{snmp_hostname} : "localhost";
	my $community 	= defined $oid_settings->{snmp_community} ? $oid_settings->{snmp_community} : "private";
	my $port 		= defined $oid_settings->{snmp_port} ? $oid_settings->{snmp_port} : 161;
	
	#my $class = ref($proto) || $proto;
	$self->{CFG} = $cfg;
	my @params_list;
	$self->{PARAMS_LIST} = [];
	my $OID = {};
	$OID->{root_OID} = $cfg->{'root_OID'};
	$OID->{service}->{name} = $service;
	$OID->{service}->{oid} = $cfg->{$service};
	$OID->{application}->{name} = $application;
	$OID->{application}->{oid} =$cfg->{$application};
	$OID->{thread}->{oid} = $thread;
	$OID->{params_groups}->{count} = 0;
	$OID->{params_groups}->{items} = {};

	$self->{SNMP_SESSION} = &init_snmp($hostname, $community, $port);
	$self->{OID} = $OID;
	$self->{app_oid} = $self->{OID}->{root_OID}.".".$self->{OID}->{service}->{oid}.".".$self->{OID}->{application}->{oid}.".".$self->{OID}->{thread}->{oid};
    bless($self, $type);
    return $self;
};

sub DESTROY {
	my $self = shift;
};

sub init_snmp {
	my ($hostname, $community, $port) = @_;
	my ($session, $error) = Net::SNMP->session
						(
							-hostname => $hostname,
							-community => $community,
							-port => $port,
							-version => 1
						);
	return $session;
}

sub add_param {
    my ($self, $in_params);
    ($self, %$in_params) = @_;

	my $params_group_name = $in_params->{params_group_name};
	my $param_name = $in_params->{param_name};
	my $param_oid = $in_params->{param_node};
	if ((!defined $param_name) && (defined $param_oid)) { $param_name = $param_oid };
	my $param_type = defined $in_params->{param_type} ? $in_params->{param_type} : INTEGER;	
	if ((!defined $params_group_name) || (!defined $param_name)) {
		return undef;
	};
	my $param_init_value = $in_params->{param_init_value};
	if (!defined $param_init_value) {
		switch ($param_type) {
			case INTEGER { $param_init_value = 0 }
			case OCTET_STRING { $param_init_value = "" }
		}
	};
	
	my $clear_after_read = defined $in_params->{clear_after_read} ? $in_params->{clear_after_read} : 0;
	
	
	my $result = {};
	my $params_groups = $self->{OID}->{params_groups};
	#my $
	if (!defined $params_groups->{items}->{$params_group_name}) {
		$params_groups->{items}->{$params_group_name} = {};
		$params_groups->{count} ++;
	}
	my $params_group = $params_groups->{items}->{$params_group_name};
	$params_group->{oid} = $self->{CFG}->{$params_group_name};
	$params_group->{items}->{$param_name}->{name} = $param_name;
	if (defined $param_oid) {
		$params_group->{items}->{$param_name}->{oid} = $param_oid;
	} else {
		$params_group->{items}->{$param_name}->{oid} = $self->{CFG}->{$param_name};
	};
	$params_group->{items}->{$param_name}->{type} = $param_type;
	$params_group->{items}->{$param_name}->{clear_after_read} = $clear_after_read;
	$params_group->{items}->{$param_name}->{value} = $param_init_value;
	
	$result->{service} 		= $self->{OID}->{service};
	$result->{application} 	= $self->{OID}->{application};
	$result->{thread} 		= $self->{OID}->{thread};
	$result->{application} 	= $self->{OID}->{application};
	$result->{params_group}->{name} = $params_group_name;
	$result->{params_group}->{oid}	= $self->{CFG}->{$params_group_name};
	$result->{param}		= $self->{OID}->{params_groups}->{items}->{$params_group_name}->{items}->{$param_name};
	
	$result->{param_oid} = $self->{app_oid}.".".$result->{params_group}->{oid}.".".$result->{param}->{oid};
	#my @params_list = @{$self->{PARAMS_LIST}};
	push(@{$self->{PARAMS_LIST}}, $result);
	&write_oid_to_log($result->{param}->{name}, $result->{param_oid}, $OIDS_LOG_FILE_NAME, $OIDS_LOG_HASH);
	return $result;
	#return $params_group->{items}->{$param_name};
};

sub param_set_value {
	my ($self, $param, $value) = @_;
	$param->{param}->{value} = $value;
	&check_flush_trigger($self, $param);
}

sub param_increment_value {
	my ($self, $param, $value) = @_;
	$param->{param}->{value} += $value;
	&check_flush_trigger($self, $param);
}

sub set_flush_params {
    my ($self, $param, $in_params);
    ($self, $param, %$in_params) = @_;

	my $write_action = defined $in_params->{write_action} ? $in_params->{write_action} : 0; 		# определяет действие над переменной при ее модификации
																									# 0 - значение переменной замещается
																									# 1 - значение переменной инкрементируется
	my $trigger_value = defined $in_params->{trigger_value} ? $in_params->{trigger_value} : 0; 		# 0 - означает, что триггер неактивен
	my $empty_on_flush = defined $in_params->{empty_on_flush} ? $in_params->{empty_on_flush} : 1;
	my $flush_all_params_on_trigger_event = defined $in_params->{flush_all_params_on_trigger_event} ? 
											$in_params->{flush_all_params_on_trigger_event} : 0;

	#my ($self, $param, $write_action, $trigger_value, $empty_on_flush) = @_;
	
	#if (!defined $empty_on_flush) {
	#	$empty_on_flush = 1;
	#}
	
	$param->{flush_settings}->{write_action} = $write_action;  
	$param->{flush_settings}->{flush_trigger}->{value} = $trigger_value;
	$param->{flush_settings}->{flush_trigger}->{empty_on_flush} = $empty_on_flush;
	$param->{flush_settings}->{flush_trigger}->{flush_all_params_on_trigger_event} = $flush_all_params_on_trigger_event;
} 

sub check_flush_trigger {
	my ($self, $param) = @_;
	if ($param->{flush_settings}->{flush_trigger}->{value} == 0) { return };  # Триггер не включен, выходим
	if ($param->{flush_settings}->{flush_trigger}->{value} <= $param->{param}->{value}) {
		&flush_param($self, $param);
		
	}
}

sub flush_param {
	my ($self, $param) = @_;
	my $node = $self->{OID}->{root_OID};
	$node .= ".".$param->{service}->{oid};
	$node .= ".".$param->{application}->{oid};
	$node .= ".".$param->{thread}->{oid};
	$node .= ".".$param->{params_group}->{oid};
	$node .= ".".$param->{param}->{oid};
		
	$node .= ".".$param->{flush_settings}->{write_action};
	my $t;
	switch ($param->{param}->{type}) {
		case INTEGER { $t = 0 }
		case OCTET_STRING { $t = 1 }
	};
	$node .= ".".$t.".".$param->{param}->{clear_after_read};
	my( @list);     
	push( @list, ($node, $param->{param}->{type}, $param->{param}->{value}));  
	my $result = $self->{SNMP_SESSION}->set_request(-varbindlist => [@list]);
	if ($param->{flush_settings}->{flush_trigger}->{empty_on_flush}) {
		switch ($param->{param}->{type}) {
			case INTEGER { $param->{param}->{value} = 0 }
			case OCTET_STRING { $param->{param}->{value} = "" }
		};
	};
	return $result; # результат содержит hash с одним элементом oid => value
};

sub flush_all {
	my ($self) = @_;
	
	my @params_list = @{$self->{PARAMS_LIST}};
	my $result ={};
	my $var_count = 0;
	
	foreach my $param (@params_list)
	{
		my $flush_result = &flush_param($self, $param);
		while ( my ($key, $value) = each(%$flush_result) ) {
			$result->{$key} = $value;
			last;
    	};
    	$var_count ++;
	}
	return ($result, $var_count);
}

# рекурсивное создание каталога
# возврашает 1 в случае успеха и 0 - если ошибка
sub rmkdir{
	my($tpath) = @_;
	my($dir, $accum) = ('', '');
	my $result = 1;
	foreach $dir (split(/\//, $tpath)){
		$accum = "$accum$dir/";
		if($dir ne ""){
			if(! -d "$accum"){
				my $res = mkdir $accum;
				if (!$res) {
					$result = 0;
					last;
				}
			}
		}
	};
	return $result;
};

sub init_oids_log {
	my ($file_name) = @_;
	open(LOG, '>'.$file_name);
	print(LOG "");
	close(LOG);
};

sub read_oids_from_log {
	my ($file_name, $hash_tmp) = @_;
	if (-e $file_name) {
		if (open(LOG, '<'.$file_name)) {
			while (<LOG>) {
				if ($_ =~ /^([a-zA-Z0-9\_]+)\s*\=\s*(.*)$/) {
					my $v = $2;
					my $ky = $1;
					$hash_tmp->{$ky} = $v;
				};
			};
		};
		close(LOG);
	};
};

sub write_oid_to_log {
	my ($param_name, $param_oid, $file_name, $hash_tmp) = @_;
	
	if (!defined $hash_tmp->{$param_name}) {
		$hash_tmp->{$param_name} = $param_oid;
	};
	
	if (open(LOG, '>'.$file_name)) {
		foreach my $key (keys %$hash_tmp) {
			print(LOG $key."=".$hash_tmp->{$key}."\n");
		};
		close(LOG);
	};
};


1;

__END__

=head1 EXAMPLES

# Пример скрипта, управляющего значениями в OID`s  
#      enterprises.2022.1.999.1.7.9 enterprises.2022.1.999.1.7.10 enterprises.2022.1.999.1.7.11

use strict; 
use Net::SNMP; 
use lib qw(/home/projects/SHARED_API);
use lib qw(/home/projects/snmp);
use cfg;
use SNMP_API;
use Time::HiRes qw(usleep);
use Math::Round qw(:all);  

my $cfg = cfg::parseConfig( '/home/projects/snmp/oids.ini' );

# ВНИМАНИЕ!!! Все имена должны быть описаны в файле /home/projects/snmp/oids.ini

# Пример ini файла
=pod
# корневой OID
root_OID=".1.3.6.1.4.1.2022"

# сервисы/витрины 1-й уровень
#   service_[service name]
service_USSD="1"
service_SIM="2"

# приложения 2-й уровень
#   app_[application name]
app_ussd_portal="3"
app_sim_portal="4"
app_icb_portal="5"
app_snmp_test="999"

# номер потока 3-й уровень
# нумерация от 1 до ...

# группы параметров для мониторинга 4-й уровень
#   params_group_xxxxxxxx
params_group_input="6"
params_group_partners="7"

# мониторинг партнерских параметров 5-й уровень
#   param_yyyyyyyy
param_requests_count="9"
param_errors_count="10"
param_errors_percent="11"

=cut

my $snmp_intf = new SNMP_INTF($cfg, 'service_USSD', 'app_snmp_test', 1);

my $snmp_param_1 = $snmp_intf->add_param(
										params_group_name => 'params_group_partners', 
										param_name => 'param_requests_count', 
										param_type => INTEGER,
										clear_after_read => 1,   # очищать переменную после прочтения из нее данных
										param_init_value => 0
										);
										
my $snmp_param_2 = $snmp_intf->add_param(
										params_group_name => 'params_group_partners', 
										param_name => 'param_errors_count', 
										param_type => INTEGER, 
										clear_after_read => 1,   # очищать переменную после прочтения из нее данных
										param_init_value => 0
										);

my $snmp_param_3 = $snmp_intf->add_param(
										params_group_name => 'params_group_partners', 
										param_name => 'param_errors_percent', 
										param_type => INTEGER, 
										clear_after_read => 1,   # очищать переменную после прочтения из нее данных
										param_init_value => 0
										);

#my $snmp_param_4 = $snmp_intf->add_param(
#										params_group_name => 'params_group_partners', 
#										param_name => 'param_errors_count', 
#										param_type => OCTET_STRING, 
#										param_init_value => "test value"
#										);

$snmp_intf->set_flush_params($snmp_param_1, write_action => 1, trigger_value => 0, empty_on_flush => 1);  
$snmp_intf->set_flush_params($snmp_param_2, write_action => 1, trigger_value => 0, empty_on_flush => 1);  
$snmp_intf->set_flush_params($snmp_param_3, write_action => 1, trigger_value => 0, empty_on_flush => 1);  

my $i = 1000;
my $j = 0;
my ($num_req, $num_err, $err_percent);
while (1) {
	sleep(5);
	$num_req = round(500 + rand(500));
	$num_err = round(30 + rand(200));
	$err_percent = round(($num_err/$num_req)*100);
	$snmp_intf->param_increment_value($snmp_param_1, $num_req);
	$snmp_intf->param_increment_value($snmp_param_2, $num_err);
	$snmp_intf->param_increment_value($snmp_param_3, $num_req);
	$snmp_intf->flush_all;
};


=cut
