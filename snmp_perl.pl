#!/usr/bin/perl -w
##
## SNMPD perl initialization file.
##

## Этот модуль цепляется в /etc/snmp/snmpd.conf
##  обслуживает ветку .1.3.6.1.4.1.2022
##   disablePerl false
##   perl do "/home/projects/SHARED_API/snmp_perl.pl"


use NetSNMP::OID (':all'); 
use NetSNMP::agent (':all'); 
use NetSNMP::ASN (':all');
use Sys::Syslog qw (:standard :macros);
use CGI::Fast qw/:standard :debug/;
use Switch;

my $write_to_log = 0;
if ($write_to_log) {
	openlog 'snmp_perl', "ndelay,pid", LOG_INFO|LOG_LOCAL0; 
};
slog("");

#use NetSNMP::agent;
my $agent = new NetSNMP::agent('dont_init_agent' => 1,
			    'dont_init_lib' => 1);
	


#
# Associate the handler with a particular OID tree
#
my $rootOID = ".1.3.6.1.4.1";
my $VM_OID = ".2022";
my $params_hash = {};
my $regoid = new NetSNMP::OID($rootOID.$VM_OID);
slog("regoid is ".$regoid);
$agent->register("my_agent_name", $regoid, \&myhandler_2);

#my $running = 1;
#while($running) {
#    $agent->agent_check_and_process(1);
#}
##
#$agent->shutdown();


#
# Handler routine to deal with SNMP requests
#
sub myhandler {
	my  ($handler, $registration_info, $request_info, $requests) = @_;

	for ($request = $requests; $request; $request = $request->next()) { 
		#  Work through the list of varbinds
		my $oid = $request->getOID();
		my ($i, $j) = (length($regoid), length($oid));
		my $sub_tree = substr($oid, $i + 1, $j - $i - 1);
		my $value = undef;
		my $mode = $request_info->getMode();
		my ($service, $application, $thread, $param_group, $param, $action) = ();
		if ($sub_tree =~ /(\d+).(\d+).(\d+).(\d+).(\d+).?(\d?)/) {
			($service, $application, $thread, $param_group, $param, $action) = ($1, $2, $3, $4, $5, $6);
		};
		$action = 0 if $action eq "";
		if ($mode == MODE_GET) {
			log_params($oid, $sub_tree, "MODE_GET", $service, $application, $thread, $param_group, $param, $action);
			$value = $params_hash->{$service}->{$application}->{$thread}->{$param_group}->{$param};
			if (!defined $value) {
				$value = -1;
			}
			$request->setValue(ASN_INTEGER, $value);
		} elsif ($mode == MODE_GETNEXT) {
			log_params($oid, $sub_tree, "MODE_GETNEXT", $service, $application, $thread, $param_group, $param, $action);
		    # ... generally, you would calculate value from oid
		    #if ($oid < new NetSNMP::OID($rootOID.$VM_OID.".1.1.2")) {
				$request->setOID($rootOID.$VM_OID.".1.1.2.4.10");
				#$request->setValue(ASN_OCTET_STR, $var_1_1_2);
		    #}
		} elsif ($mode == MODE_SET_RESERVE1) {
			log_params($oid, $sub_tree, "MODE_SET_RESERVE1", $service, $application, $thread, $param_group, $param, $action);
			if ($action == 0) {
		    	$params_hash->{$service}->{$application}->{$thread}->{$param_group}->{$param} = $request->getValue();
			} elsif ($action ==1) {
				if (!defined $params_hash->{$service}->{$application}->{$thread}->{$param_group}->{$param}) {
					$params_hash->{$service}->{$application}->{$thread}->{$param_group}->{$param} = 1;
				} else {
					$params_hash->{$service}->{$application}->{$thread}->{$param_group}->{$param} += 1;
				}
			}
		    #if ($oid != new NetSNMP::OID($rootOID.$VM_OID.".1.1.2")) {  # do error checking here
		    #	slog("вот тут ошибочка вышла");
			#	$request->setError($request_info, SNMP_ERR_NOSUCHNAME);
		    #}
		} elsif ($mode == MODE_SET_ACTION) {
			#slog("Mode is MODE_SET_ACTION(".MODE_SET_ACTION.")");
			#slog("Зашли поменять значение");
		    # ... (or use the value)
		    #$params_hash->{$service}->{$application}->{$thread}->{$param_group}->{$param} = $request->getValue();
		} else {
			log_params($oid, $sub_tree, $mode, $service, $application, $thread, $param_group, $param, $action);
		}
	}
}

sub myhandler_2 {
	my  ($handler, $registration_info, $request_info, $requests) = @_;

	for ($request = $requests; $request; $request = $request->next()) { 
		#slog($request_info);
		#  Work through the list of varbinds
		my ($oid, $oid_type, $oid_value) = $request->getOID();
		my ($i, $j) = (length($regoid), length($oid));
		my $sub_tree = substr($oid, $i + 1, $j - $i - 1);
		my $value = undef;
		my $mode = $request_info->getMode();
		#my $type = getType();
		#slog($type);
		my ($action, $var_type, $clear_on_read) = ();
		if (($mode == MODE_SET_RESERVE1) && ($sub_tree =~ /(\S+).(\d+).(\d+).(\d+)$/)) {
			$sub_tree = $1;
			$action = $2;  	# 0 - передается абсолютное значение переменной
							# 1 - переменную необходимо инкрементировать на передаваемое значение
			$var_type = $3; # тип передаваемого значения
							# 0 - INTEGER
							# 1 - OCTET_STRING
			$clear_on_read = defined $4 ? $4 : 0; # очищать переменную после команды MODE_GET
		};
		$action = 0 if $action eq "";
		if ($mode == MODE_GET) {
			
			#foreach my $key_tmp (sort keys %$params_hash) {
			#	slog($key_tmp."=".$params_hash->{$key_tmp});
			#}

			
			log_params2(oid => $oid, sub_tree => $sub_tree, mode => "MODE_GET");
			if (defined $params_hash->{$sub_tree}) {
				$value = $params_hash->{$sub_tree}->{'value'};
				$var_type = $params_hash->{$sub_tree}->{'type'};
				$clear_on_read = defined $params_hash->{$sub_tree}->{'clear_on_read'} ? $params_hash->{$sub_tree}->{'clear_on_read'} : 0;
				#if (!defined $value) {
				#	$value = -1;
				#	$var_type = 0;
				#}
				switch ($var_type) {
					case 0 {
							$var_type = ASN_INTEGER;
							$params_hash->{$sub_tree}->{'value'} = 0 if $clear_on_read;
							}
					case 1 {
							$var_type = ASN_OCTET_STR;
							$params_hash->{$sub_tree}->{'value'} = "" if $clear_on_read;
							}
				};
				$request->setValue($var_type, $value);
			};
		} elsif ($mode == MODE_GETNEXT) {
			log_params2(oid => $oid, sub_tree => $sub_tree, mode => "MODE_GETNEXT");
	    	my ($v, $c, $empty_flag);
	    	if ($sub_tree eq '') {
	    		slog("sub-tree is empty string");
	    		$empty_flag = 1;
	    	} else {
	    		$empty_flag = 0;
	    	};
	    	($sub_tree, $v, $c) = get_next_hash_key($params_hash, $sub_tree);
	    	slog("sub-tree is ".$sub_tree." now");
	    	#if (!defined $c) {
	    	#	$c = new NetSNMP::OID($rootOID.$VM_OID.".9999");
	    	#	$request->setOID($c);
	    	#} else {
	    	#	if (!$empty_flag) {
	    	#		$sub_tree = $c;
	    	#	}
				$request->setOID($rootOID.$VM_OID.".".$sub_tree);
	    	#};
			switch ($v->{'type'}) {
				case 0 { $var_type = ASN_INTEGER; }
				case 1 { $var_type = ASN_OCTET_STR; }
			};
			$request->setValue($var_type, $v->{'value'});
			if (!defined $c) {
				$request->setOID(undef);
			};
		} elsif ($mode == MODE_SET_RESERVE1) {
			log_params2(oid => $oid, sub_tree => $sub_tree, mode => "MODE_SET_RESERVE1", 
						action => $action, var_type => $var_type, clear_on_read => $clear_on_read);
			if (!defined $params_hash->{$sub_tree}) {
				$params_hash->{$sub_tree}->{'type'} = $var_type;
				$params_hash->{$sub_tree}->{'clear_on_read'} = $clear_on_read;
				if ($var_type == 0) {
					$params_hash->{$sub_tree}->{'value'} = 0;
				} elsif ($var_type == 1) {
					$params_hash->{$sub_tree}->{'value'} = "";
				};
			};
			if (($action == 0) || ($var_type == 1)) {  # если тип - строка  или действие - перезапись значения
		    	$params_hash->{$sub_tree}->{'value'} = $request->getValue();
			} elsif (($action == 1) && ($var_type == 0)) { # если тип - число и действие - инкремент
				$params_hash->{$sub_tree}->{'value'} += $request->getValue();
			};
		} elsif ($mode == MODE_SET_ACTION) {
			#slog("Mode is MODE_SET_ACTION(".MODE_SET_ACTION.")");
			#slog("Зашли поменять значение");
		    # ... (or use the value)
		    #$params_hash->{$service}->{$application}->{$thread}->{$param_group}->{$param} = $request->getValue();
		} else {
			#log_params($oid, $sub_tree, $mode, $service, $application, $thread, $param_group, $param, $action);
		}
	}
}


sub log_params {
	my ($oid, $sub_tree, $mode, $service, $application, $thread, $param_group, $param, $action) = @_;
	slog("");
	slog("Entered to handler...");
	slog("OID is ".$oid);
	slog("Sub-tree is ".$sub_tree);
	slog("request_mode is ".$mode);
	slog("Service is ".$service);
	slog("Application is ".$application);
	slog("Thread is ".$thread);
	slog("Param_group is ".$param_group);
	slog("Param is ".$param);
	slog("Action is ".$action);
}

sub log_params2 {
    my $in_params;
    %$in_params = @_;

	while ( my ($key, $value) = each(%$in_params) ) {
		slog("$key => $value");
	};
	slog("");
}

sub get_first_hash_element {
	my $hash_tmp = @_;
	slog("get_first_hash_element function");
	my $result = undef;
	foreach my $key_tmp (sort keys %$hash_tmp) {
		$result = $key_tmp;
		slog($key_tmp."=>".$hash_tmp->{$key_tmp});
		last;
	};
	return $result;
};

sub get_next_hash_key {
	my ($hash_tmp, $curr_key) = @_;
	my $curr_value = $hash_tmp->{$curr_key};
	my $next_key = undef;
	my $found_entry = 0;
	slog("get_next_hash_key function");
	foreach my $key_tmp (sort keys %$hash_tmp) {
		slog($key_tmp."=".$hash_tmp->{$key_tmp});
		if (!defined $curr_value) {
			$curr_key = $key_tmp;
			$curr_value = $hash_tmp->{$curr_key};
		}
		if ($found_entry) {
			$next_key = $key_tmp;
			last;
		};
		if (($key_tmp eq $curr_key) && (!$found_entry)) {
			$found_entry = 1;
		}
	}
	return ($curr_key, $curr_value, $next_key);
}

sub slog {
	if (!$write_to_log) { return };
	my ($strf,@args) = @_;
	my $rh = remote_host();
	if (scalar(@args) > 0) {
	  if ($rh ne "") {
		syslog(LOG_INFO,"From: ".$rh." ".$strf,@args);
	  } else {
		syslog(LOG_INFO,$strf,@args);
	  };
	} else {
	  if ($rh ne "") {
		syslog(LOG_INFO,"From: ".$rh." ".$strf);
	  } else {
		syslog(LOG_INFO,$strf);
	  };
	};
};
