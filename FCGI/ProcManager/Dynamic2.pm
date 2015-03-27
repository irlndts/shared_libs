package FCGI::ProcManager::Dynamic2;
use base FCGI::ProcManager;

# Copyright (c) 2012, Andrey Velikoredchanin.
# This library is free software released under the GNU Lesser General
# Public License, Version 3.  Please read the important licensing and
# disclaimer information included below.

# $Id: Dynamic.pm,v 0.6 2012/06/29 11:00:00 Andrey Velikoredchanin $

use strict;

use vars qw(
	$VERSION
);


BEGIN {
	$VERSION = '0.6';
}

use POSIX;
use Time::HiRes qw(usleep);
use IPC::SysV qw(IPC_PRIVATE IPC_CREAT IPC_NOWAIT IPC_RMID);
use FCGI::ProcManager qw($SIG_CODEREF);

#use Net::SNMP;
use lib qw(/home/projects/SHARED_API);
#use snmp;
use cfg;


=head1 NAME

FCGI::ProcManager::Dynamic -  extension for FCGI::ProcManager, it can dynamically control number of work processes depending on the load.

=head1 SYNOPSIS

 # In Object-oriented style.
 use CGI::Fast;
 use FCGI::ProcManager::Dynamic;
 my $proc_manager = FCGI::ProcManager::Dynamic->new({
 	n_processes => 8,
 	min_nproc => 8,
 	max_nproc => 32,
 	delta_nproc => 4,
 	delta_time => 60,
 	max_requests => 300
 });
 $proc_manager->pm_manage();
 while ($proc_manager->pm_loop() && (my $cgi = CGI::Fast->new())) {
 	$proc_manager->pm_pre_dispatch();
 	# ... handle the request here ...
 	$proc_manager->pm_post_dispatch();
 }

=head1 DESCRIPTION

FCGI::ProcManager::Dynamic the same as FCGI::ProcManager, but it has additional settings and functions for dynamic control of work processes's number.

=head1 Addition options

=head2 min_nproc

The minimum amount of worker processes.

=head2 max_nproc

The maximum amount of worker processes.

=head2 delta_nproc

amount of worker processes which will be changed for once in case of their increase or decrease.

=head2 delta_time

Delta of time from last change of processes's amount, when they will be reduced while lowering of loading.

=head2 max_requests

Amount of requests for one worker process. If it will be exceeded worker process will be recreated.

=head1 Addition functions

=head2 pm_loop

Function is needed for correct completion of worker process's cycle if max_requests will be exceeded.

=head1 BUGS

No known bugs, but this does not mean no bugs exist.

=head1 SEE ALSO

L<FCGI::ProcManager>
L<FCGI>

=head1 MAINTAINER

Andrey Velikoredchanin <andy@andyhost.ru>

=head1 AUTHOR

Andrey Velikoredchanin

=head1 COPYRIGHT

FCGI-ProcManager-Dynamic - A Perl FCGI Dynamic Process Manager
Copyright (c) 2012, Andrey Velikoredchanin.

This library is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 3 of the License, or (at your option) any later version.

BECAUSE THIS LIBRARY IS LICENSED FREE OF CHARGE, THIS LIBRARY IS
BEING PROVIDED "AS IS WITH ALL FAULTS," WITHOUT ANY WARRANTIES
OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING, WITHOUT
LIMITATION, ANY IMPLIED WARRANTIES OF TITLE, NONINFRINGEMENT,
MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, AND THE
ENTIRE RISK AS TO SATISFACTORY QUALITY, PERFORMANCE, ACCURACY,
AND EFFORT IS WITH THE YOU.  See the GNU Lesser General Public
License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307  USA

=cut


sub pm_manage {
	my $self = shift;

	$self->{USED_PROCS} = 0;

	if (!defined($self->{min_nproc})) { $self->{min_nproc} = $self->n_processes(); };
	if (!defined($self->{max_nproc})) { $self->{max_nproc} = 8; };
	if (!defined($self->{delta_nproc})) { $self->{delta_nproc} = 5; };
	if (!defined($self->{delta_time})) { $self->{delta_time} = 5; };
	if (!defined($self->{proc_time_to_live})) { $self->{proc_time_to_live} = 60; };

	# настраиваем SNMP
	#my $oids_ini = "/home/projects/SHARED_API/FCGI/ProcManager/oids.ini";
	#if (-e $oids_ini) {
	#	$self->init_snmp($oids_ini);
	#} else {
	#	$self->pm_notify("oids.ini not found");
	#};
	
	# некоторые константы
	# ожидание завершения процесса после получения сигнала TERM
	if (!defined($self->{exit_on_term_wait_timeout})) { $self->{exit_on_term_wait_timeout} = 90; };
	# ожидание завершения процесса после получения сигнала KILL
	if (!defined($self->{exit_on_kill_wait_timeout})) { $self->{exit_on_kill_wait_timeout} = 10; };
	# ожидание обновления метки времени для свободного процесса
	if (!defined($self->{time_label_refresh_period_for_free})) { $self->{time_label_refresh_period_for_free} = 180; };
	# ожидание обновления метки времени для занятого процесса
	if (!defined($self->{time_label_refresh_period_for_busy})) { $self->{time_label_refresh_period_for_busy} = 120; };
	
	$self->{_last_delta_time} = time();

	# Создает очередь сообщений
	if (!($self->{ipcqueue} = msgget(IPC_PRIVATE, IPC_CREAT | 0666))) {
		die "Cannot create shared message pipe!";
	};

	#$self->{USEDPIDS} = {};
	
	#$self->pm_parameter('pm_title', $self->{fcgi_main_proc_name}) if defined $self->{fcgi_main_proc_name};

	$self->{pm_title} = $self->{fcgi_main_proc_name} if defined $self->{fcgi_main_proc_name};

	$self->{pm_die_flag} = 0;
	$self->{last_info_time} = time() - 600;
	$self->pm_notify("servers count must be equal to $self->{n_processes}");
	#$self->{pm_exit_child_timeout} = 60;
	$self->SUPER::pm_manage();
	my $t = time();
	$self->{PIDS}->{$$}->{last_time_label} = $t;
	#рабочий статус процесса  0 - свободен, 1 - в работе, 2 - получил TERM, 3 - получил KILL
	$self->{PIDS}->{$$}->{proc_status} = 0;
};

#sub init_snmp {
#	my ($self, $oids_ini) = @_;
#	$self->pm_notify("oids_ini is $oids_ini");
#	my $cfg_snmp = cfg::parseConfig($oids_ini); 
#	if ((!defined $self->{service_name}) || (!defined $self->{application_name})) {
#		return;
#	};
#	$self->{snmp_intf} = new SNMP_INTF($cfg_snmp, snmp_hostname => 'localhost',
#											 snmp_community => 'private',
#											 snmp_port => 161,
#											 service_name => $self->{service_name}, 
#											 app_name => $self->{application_name}, 
#											 thread_no => 1);
#	$self->{snmp_servers_count_var} = $self->{snmp_intf}->add_param(params_group_name => 'params_group_app_health', 
#									   								param_name => 'param_fcgi_child_count',   # счетчик количества запущенных fcgi чайлдов
#									   								param_type => INTEGER,
#									   								param_init_value => 0);
#	if (defined $self->{snmp_servers_count_var}) {
#		$self->{snmp_intf}->set_flush_params($self->{snmp_servers_count_var}, write_action => 0, clear_after_read => 0, trigger_value => 0, empty_on_flush => 1); 
#	}; 
#};

sub pm_wait {
	my $self = shift;
	my $waitpid = 0;

	# wait for the next server to die.
	$self->pm_notify("entered to pm_wait ");
	
	my $need_new_fork_flag = 0;
	# цикл пока не получили сигнал выхода
MAIN_LOOP: 
	while ( #(!$self->{pm_die_flag}) && 
	       ($waitpid >= 0) ) {
		
		# Для информации: статистика по процессам
		my $t = time();
		if ($t - $self->{last_info_time} > 300) { # раз в 5 минут выводим в лог значение количества чайлдов, которое должно быть в системе по всем расчетам
			my ($proc_need_value, $proc_real_count, $proc_free_count, $proc_busy_count, $proc_exit_wait_count, $proc_exit_hung_count) = (0, 0, 0, 0, 0, 0);
			$proc_need_value = $self->{n_processes};
			$proc_real_count = keys(%{$self->{PIDS}});
			foreach my $pid (keys %{$self->{PIDS}}) {
				my $proc_status = $self->{PIDS}->{$pid}->{proc_status};
				if (defined ($proc_status)) {
					if ($proc_status == 0) {
						$proc_free_count++;
					} elsif ($proc_status == 1) {
						$proc_busy_count++;
					} elsif ($proc_status == 2) {
						$proc_exit_wait_count++;
					} elsif ($proc_status == 3) {
						$proc_exit_hung_count++;
					};
				};
			};
			$self->pm_notify("Statistics: proc_need/proc_real/proc_free/proc_busy/proc_exit_wait/proc_exit_hung  $proc_need_value/$proc_real_count/$proc_free_count/$proc_busy_count/$proc_exit_wait_count/$proc_exit_hung_count");
			$self->{last_info_time} = $t;
			#if (defined $self->{snmp_servers_count_var}) {
			#	$self->{snmp_intf}->param_set_value($self->{snmp_servers_count_var}, $proc_real_count);
			#	my ($flush_results, $flush_count) = $self->{snmp_intf}->flush_param($self->{snmp_servers_count_var});
			#	while (my ($key, $value) = each(%$flush_results) ) {
			#		$self->pm_notify($key." => ".$value);
			#	};
			#};
		};
		
		# проверим, может кто "умер"
		GET_CHILD_STATUSES: 
			while (1) {
				$waitpid = waitpid(-1, WNOHANG);
				if ($waitpid > 0) {
					# Удаляем PID из списка рабочих процессов
					delete($self->{PIDS}->{$waitpid});
					$self->pm_notify("server (pid $waitpid) exited with status ".$?);
					$need_new_fork_flag = 1;
				} else {
					last GET_CHILD_STATUSES;
				};
			};
		# если были выходы, даем возможность ProcManager`у восстановить баланс процессов (если не получили сигнал завершения)
	 	if ( ($need_new_fork_flag) && (!$self->{pm_die_flag}) ) {
			last MAIN_LOOP;
		};
		#$self->pm_notify("Last result of Waitpid = $waitpid");
		
		# пройдем по списку процессов, получивших сигнал SIGTERM
		# на предмет определения процессов, которые завершаются более 60 секунд
		# такие процессы завершим принудительно сигналом SIGKILL
		my $time = time();
		my $need_check_signals = 0;
		foreach my $pid (keys %{$self->{PIDS}}) {
			my $proc_status = $self->{PIDS}->{$pid}->{proc_status};
			if (defined $proc_status && ( ($proc_status == 2) || ($proc_status == 3)) ) {
				# работаем только со статусами завершения работы
				my $send_sig_time = $self->{PIDS}->{$pid}->{SEND_SIG_TIME};
				if ( ($proc_status == 3) && ($time - $send_sig_time > $self->{exit_on_kill_wait_timeout}) ) {
					# зависание на сигнале SIGKILL, что-то надо с этим делать. Пока не понятно, что именно с этим делать
					$self->pm_notify("server (pid $pid) ignored SIGKILL signal. CRITICAL");
				} elsif ( ($proc_status == 2) && ( ($time - $send_sig_time) > $self->{exit_on_term_wait_timeout}) ) {
					# зависание на сигнале SIGTERM
					# приговаривается к электрическому стулу
					$self->pm_notify("server (pid $pid) ignored SIGTERM signal, send SIGKILL to it");
					kill(SIGKILL, $pid);
					# запомним статус и время, когда послали процессу сигнал завершения
					$self->{PIDS}->{$pid}->{proc_status} = 3;
					$self->{PIDS}->{$pid}->{SEND_SIG_TIME} = time();
					$need_check_signals = 1;
				};
			};
		};
		if ($need_check_signals) {
			next MAIN_LOOP;
		};		
		
		
		# следующий блок выполняется, если приложение не получило команду на завершение
		if (!$self->{pm_die_flag}) {
			
			# проверим временнЫе метки
			# метки проверяем для процессов с рабочим статусом 0 или 1
			$t = time();
			foreach my $pid (keys %{$self->{PIDS}}) {
				if (!defined($self->{PIDS}->{$pid}->{last_time_label})) {
					# метки почему-то нет, придется установить
					$self->{PIDS}->{$pid}->{last_time_label} = $t;
					# заодно и начальный статус
					$self->{PIDS}->{$pid}->{proc_status} = 0;
				} else {
					# метка времени есть, проверим, как давно она обновлялась
					my $delta_time = $t - $self->{PIDS}->{$pid}->{last_time_label};
					if ( ( ($delta_time > $self->{time_label_refresh_period_for_free}) && ($self->{PIDS}->{$pid}->{proc_status} == 0) ) || 
						 ( ($delta_time > $self->{time_label_refresh_period_for_busy}) && ($self->{PIDS}->{$pid}->{proc_status} == 1) ) ) {
						# прошло более 60 секунд для свободного процесса или более 120 секунд для занятого процесса, 
						# время процесса не обновляется. Однозначно не можем сказать завис процесс или нет
						# самое время послать ему TERM (пока беда не случилась)
						$self->pm_notify("send SIGTERM to server $pid because last_time_label not refreshed");
						kill(SIGTERM, $pid);
						# запомним статус и время, когда послали процессу сигнал завершения
						$self->{PIDS}->{$pid}->{proc_status} = 2;
						$self->{PIDS}->{$pid}->{SEND_SIG_TIME} = time();
					};
				};
			};
		
			# Читаем сообщения
			my $rcvd;
			# вычитываем все сообщения от рабочих процессов
			while (msgrcv($self->{ipcqueue}, $rcvd, 60, 0, IPC_NOWAIT)) {
				my ($code, $pid) = unpack("l! l!", $rcvd);
				my $proc_status;
				if ($code eq '1') {
					# процесс взял запрос в обработку
					# запомним статус
					$proc_status = 1;
					#$self->{PIDS}->{$pid}->{proc_status} = 1;
				}
				elsif ($code eq '2') {
					# процесс завершил обработку запроса
					# запомним статус
					$proc_status = 0;
					#$self->{PIDS}->{$pid}->{proc_status} = 0;
				}
				elsif ($code eq '3') {
					# процесс информирует о завершении своей работы по достижению лимита на количество запросов
					$self->pm_notify("server (pid $pid) terminates by reason of max_requests");
					# запомним статус и время начала выхода
					$proc_status = 2;
					#$self->{PIDS}->{$pid}->{proc_status} = 2;
					#$self->{PIDS}->{$pid}->{SEND_SIG_TIME} = time();
				};
				# если процесс еще не завершился (а такое очень возможно), обновим статус в хеше
				if (defined $self->{PIDS}->{$pid}) {
					# обновим временнУю метку
					$self->{PIDS}->{$pid}->{last_time_label} = time();
					if (defined $proc_status) {
						$self->{PIDS}->{$pid}->{proc_status} = $proc_status;
						if ($proc_status == 2) {
							$self->{PIDS}->{$pid}->{SEND_SIG_TIME} = $self->{PIDS}->{$pid}->{last_time_label};
						};
					};
				};
			};

			# Сверяем нет-ли в списке загруженных PID уже удаленных и считаем количество используемых
			$self->{USED_PROCS} = 0;
			$t = time();
			foreach my $pid (keys %{$self->{PIDS}}) {
				my $proc_status = $self->{PIDS}->{$pid}->{proc_status};
				if ( $self->{PIDS}->{$pid}->{proc_status} == 1) {
					$self->{USED_PROCS}++;
				};
			};

			# Балансировка процессов (если получен сигнал завершения, никакой балансировки)
			# Если загружены все процессы, добавляем
			if ($self->{USED_PROCS} >= $self->{n_processes}) {
				# Добавляем процессы
				my $newnp = (($self->{n_processes} + $self->{delta_nproc}) < $self->{max_nproc}) ? ($self->{n_processes} + $self->{delta_nproc}):$self->{max_nproc};
	
				if ($newnp != $self->{n_processes}) {
					$self->pm_notify("increase servers count to $newnp");
					$self->SUPER::n_processes($newnp);
					#$waitpid = -10;
					$self->{_last_delta_time} = time();
					# Сразу переходим на fork новых процессов
					last MAIN_LOOP;
				};
			}
			elsif (($self->{USED_PROCS} < $self->{min_nproc}) && ((time() - $self->{_last_delta_time}) >= $self->{delta_time})) {
				# Если загруженных процессов меньше минимального количества, уменьшаем на delta_nproc до минимального значения
				my $newnp = (($self->{n_processes} - $self->{delta_nproc}) > $self->{min_nproc})? ($self->{n_processes} - $self->{delta_nproc}):$self->{min_nproc};
				if ($newnp != $self->{n_processes}) {
					$self->pm_notify("decrease servers count to $newnp");
					#my $i = $self->{n_processes} - $newnp;
					$self->SUPER::n_processes($newnp);
					
					#FOR_EACH: 
					#	foreach my $pid (keys %{$self->{PIDS}}) {
					#		if ($i <= 0) {
					#			last FOR_EACH;
					#		};
					#		# выставим нужному количеству процессов особый флаг, прочитав который процесс обязан прекратить работу
					#		$self->{PIDS}->{$pid}->{exit_on_end} = 1;
					#		$i--;
					#	};
					
					# В цикле убиваем нужное количество незанятых процессов
					#my $i = 0;
					#FOR_EACH_LABEL: foreach my $pid (keys %{$self->{PIDS}}) {
					#	# Убиваем только если процесс свободен
					#	if ($self->{PIDS}->{$pid}->{proc_status} == 0) {
					#		$i++;
					#		if ($i <= ($self->{n_processes} - $newnp)) {
					#			$self->pm_notify("send SIGTERM to server $pid");
					#			kill(SIGTERM, $pid);
					#			# запомним статус и время, когда послали процессу сигнал завершения
					#			$self->{PIDS}->{$pid}->{proc_status} = 2;
					#			$self->{PIDS}->{$pid}->{SEND_SIG_TIME} = time();
					#		}
					#		else {
					#			$i--;
					#			last FOR_EACH_LABEL;
					#		};
					#	};
					#};
					#if ($i) {
					#	# уменьшаем значение переменной на реальное количество процессов, получивших сигнал SIGTERM
					#	if ( ($self->{n_processes} - $i) >= $self->{min_nproc}) {
					#		$self->SUPER::n_processes($self->{n_processes} - $i);
					#		$self->{_last_delta_time} = time();
					#	} else {
					#		# попытка сделать процессов меньше, чем минимально допустимое количество процессов
					#		$self->pm_notify("attempt to set number of working servers less then  $self->{min_nproc}");
					#		# для этого случая сделаем количество процессов = минимальному
					#		$self->SUPER::n_processes($self->{min_nproc});
					#	};
					#};
				};
			}
			elsif (keys(%{$self->{PIDS}}) < $self->{n_processes}) {
				# Если количество процессов меньше текущего - добавляем
				$self->pm_notify("increase servers to ".$self->{n_processes});
				$self->{_last_delta_time} = time();
				$waitpid = -10;
			}
			elsif (keys(%{$self->{PIDS}}) < $self->{min_nproc}) {
				# Если количество процессов меньше минимального - добавляем
				$self->pm_notify("increase servers to minimal ".$self->{min_nproc});
				$self->SUPER::n_processes($self->{min_nproc});
				$self->{_last_delta_time} = time();
				$waitpid = -10;
			}
			elsif ($self->{USED_PROCS} >= ($self->{n_processes} - $self->{delta_nproc})) {
				# Если количество занятых рабочих процессов больше чем первое меньшее количество процессов относительно текущего, то отдаляем уменьшение процессов на delta_time
				$self->{_last_delta_time} = time();
			};		
		};

		if ($waitpid == 0) {
			usleep(1000000);
		};
	};

	return $waitpid;
};


=asv
sub pm_wait_ {
	my $self = shift;
	my $pid = 0;

	# wait for the next server to die.
	$self->pm_notify("entered to pm_wait ");
	
	while ($pid >= 0) {
		my $t = time();
		if ($t - $self->{last_info_time} > 300) { # раз в 5 минут выводим в лог значение количества чайлдов, которое должно быть в системе по всем расчетам
			$self->pm_notify("servers count must be equal to $self->{n_processes}");
			$self->{last_info_time} = $t;
		};
		
		# проверим, может кто "умер"
		GET_CHILD_STATUSES: 
			while (1) {
				$pid = waitpid(-1, WNOHANG);
				if ($pid > 0) {
					# Удаляем PID из всех списков
					delete($self->{PIDS}->{$pid});
					delete($self->{KILL_PIDS}->{$pid});
					delete($self->{USEDPIDS}->{$pid});
					$self->pm_notify("server (pid $pid) exited with status ".$?);
				} else {
					last GET_CHILD_STATUSES;
				};
			};
				
		
		# пройдем по списку процессов, получивших сигнал SIGTERM
		# на предмет определения процессов, которые завершаются более 60 секунд
		# такие процессы завершим принудительно сигналом SIGKILL
		my $time = time();
		foreach my $cpid (keys %{$self->{KILL_PIDS}}) {
			my $sigterm_time = $self->{KILL_PIDS}->{$cpid}->{SIGTERM_TIME};
			my $sigkill_time = $self->{KILL_PIDS}->{$cpid}->{SIGKILL_TIME};
			if ((defined $sigkill_time) && ($time - $sigkill_time > 10)) {
				# зависание на сигнале SIGTERM
				$self->pm_notify("server (pid $cpid) ignored SIGKILL signal. CRITICAL");

			} else {
				if ((defined $sigterm_time) && ($time - $sigterm_time > $self->{pm_exit_child_timeout})) {
					# зависание на сигнале SIGTERM
					$self->pm_notify("server (pid $cpid) ignored SIGTERM signal, send SIGKILL to it");
					kill(SIGKILL, $cpid);
					$self->{KILL_PIDS}->{$cpid}->{SIGKILL_TIME} = $time;
					$self->{KILL_PIDS}->{$cpid}->{SIGTERM_TIME} = undef;
				};
			};
		};		
		
		# следующий блок выполняется, если приложение не получило команду на завершение
		if (!$self->{pm_die_flag}) {
			# Читаем сообщения
			my $rcvd;
			#my $delta_killed = $self->{delta_nproc};
			while (msgrcv($self->{ipcqueue}, $rcvd, 60, 0, IPC_NOWAIT)) {
				my ($code, $cpid) = unpack("l! l!", $rcvd);
				if ($code eq '1') {
					# процесс взял запрос в обработку
					$self->{USEDPIDS}->{$cpid}->{time_begin} = time();
				}
				elsif ($code eq '2') {
					# процесс завершил обработку запроса
					delete($self->{USEDPIDS}->{$cpid});
				}
				elsif ($code eq '3') {
					# процесс информирует о завершении своей работы по достижению лимита на количество запросов
					$self->pm_notify("server (pid $cpid) terminates by reason of max_requests");
				};
			};

			# Сверяем нет-ли в списке загруженных PID уже удаленных и считаем количество используемых
			# также посмотрим, кто как работает. если процесс взялся за обработку и не завершает ее дольше чем 60 сек, принудительно прихлопнем процесс
			$self->{USED_PROCS} = 0;
			$t = time();
			foreach my $cpid (keys %{$self->{USEDPIDS}}) {
				if (defined($self->{USEDPIDS}->{$cpid}->{time_begin}) && ($t - $self->{USEDPIDS}->{$cpid}->{time_begin} > 60)) {
					# посылаем TERM процессу
					$self->pm_notify("send SIGTERM to server $cpid. Reason - not answer for a long time");
					kill(SIGTERM, $cpid);
				} else {
					if (!defined($self->{PIDS}->{$cpid})) {
						delete($self->{USEDPIDS}->{$cpid});
					}
					else {
						$self->{USED_PROCS}++;
					};
				};
			};

			# Балансировка процессов (если получен сигнал завершения, никакой балансировки)
			# Если загружены все процессы, добавляем
			if ($self->{USED_PROCS} >= $self->{n_processes}) {
				# Добавляем процессы
				my $newnp = (($self->{n_processes} + $self->{delta_nproc}) < $self->{max_nproc})? ($self->{n_processes} + $self->{delta_nproc}):$self->{max_nproc};
	
				if ($newnp != $self->{n_processes}) {
					$self->pm_notify("increase servers count to $newnp");
					$self->SUPER::n_processes($newnp);
					$pid = -10;
					$self->{_last_delta_time} = time();
				};
			}
			elsif (($self->{USED_PROCS} < $self->{min_nproc}) && ((time() - $self->{_last_delta_time}) >= $self->{delta_time})) {
				# Если загруженных процессов меньше минимального количества, уменьшаем на delta_nproc до минимального значения
				my $newnp = (($self->{n_processes} - $self->{delta_nproc}) > $self->{min_nproc})? ($self->{n_processes} - $self->{delta_nproc}):$self->{min_nproc};
				if ($newnp != $self->{n_processes}) {
					$self->pm_notify("decrease servers count to $newnp");
					# В цикле убиваем нужное количество незанятых процессов
					my $i = 0;
					FOR_EACH_LABEL: foreach my $dpid (keys %{$self->{PIDS}}) {
						# Убиваем только если процесс свободен
						if (!defined($self->{USEDPIDS}->{$dpid})) {
							$i++;
							if ($i <= ($self->{n_processes} - $newnp)) {
								$self->pm_notify("send SIGTERM to server $dpid");
								kill(SIGTERM, $dpid);
								#kill(SIGKILL, $dpid);
								#delete($self->{PIDS}->{$dpid});
								# запомним время, когда послали процессу сигнал завершения
								$self->{KILL_PIDS}->{$dpid}->{SIGTERM_TIME} = time();
							}
							else {
								$i--;
								last FOR_EACH_LABEL;
							};
						};
					};
					#$self->SUPER::n_processes($newnp);
					if ($i) {
						# уменьшаем значение переменной на реальное количество процессов, получивших сигнал SIGTERM
						if ( ($self->{n_processes} - $i) >= $self->{min_nproc}) {
							$self->SUPER::n_processes($self->{n_processes} - $i);
							$self->{_last_delta_time} = time();
						} else {
							# попытка сделать процессов меньше, чем минимально допустимое количество процессов
							$self->pm_notify("attempt to set number of working servers less then  $self->{min_nproc}");
							# для этого случая сделаем количество процессов = минимальному
							$self->SUPER::n_processes($self->{min_nproc});
						};
					};
				};
			}
			elsif (keys(%{$self->{PIDS}}) < $self->{n_processes}) {
				# Если количество процессов меньше текущего - добавляем
				$self->pm_notify("increase servers to ".$self->{n_processes});
				$self->{_last_delta_time} = time();
				$pid = -10;
			}
			elsif (keys(%{$self->{PIDS}}) < $self->{min_nproc}) {
				# Если количество процессов меньше минимального - добавляем
				$self->pm_notify("increase servers to minimal ".$self->{min_nproc});
				$self->SUPER::n_processes($self->{min_nproc});
				$self->{_last_delta_time} = time();
				$pid = -10;
			}
			elsif ($self->{USED_PROCS} >= ($self->{n_processes} - $self->{delta_nproc})) {
				# Если количество занятых рабочих процессов больше чем первое меньшее количество процессов относительно текущего, то отдаляем уменьшение процессов на delta_time
				$self->{_last_delta_time} = time();
			};		
		};

		if ($pid == 0) {
			usleep(1000000);
		};
	};

	return $pid;
};
=cut

sub pm_pre_dispatch {
	my $self = shift;
	$self->SUPER::pm_pre_dispatch();

	if (!msgsnd($self->{ipcqueue}, pack("l! l!", 1, $$), IPC_NOWAIT)) {
		print STDERR "Error when execute MSGSND in pm_pre_dispatch\n";
		$self->{msgsenderr} = 1;
	} else {
		$self->{msgsenderr} = 0;
	};

	# Счетчик запросов
	if (!defined($self->{requestcount})) {
		$self->{requestcount} = 1;
	} else {
		$self->{requestcount}++;
	};
};

sub pm_post_dispatch {
	my $self = shift;

	if (!$self->{msgsenderr}) {
		msgsnd($self->{ipcqueue}, pack("l! l!", 2, $$), 0);
	};

	$self->SUPER::pm_post_dispatch();

#	# Читаем сообщения
#	my $rcvd;
#	# вычитываем все сообщения от рабочих процессов
#	if (msgrcv($self->{ipcqueue}, $rcvd, 60, 0, IPC_NOWAIT)) {
#		
#	};

	# Если определено максимальное количество запросов и оно превышено - выходим из чайлда
	#if ( (defined($self->{max_requests}) && ($self->{max_requests} ne '') && ($self->{requestcount} >= $self->{max_requests})) || 
	#     (defined $self->{PIDS}->{$$}->{exit_on_end}) ) {
	if (defined($self->{max_requests}) && ($self->{max_requests} ne '') && ($self->{requestcount} >= $self->{max_requests})) {
		if ($self->{pm_loop_used}) {
			$self->{exit_flag} = 1;
			if (!$self->{msgsenderr}) {
				# информируем manager о том, что исчерпали лимит на обработку запросов
				msgsnd($self->{ipcqueue}, pack("l! l!", 3, $$), 0);
			};
		} else {
			# Если в цикле не используется pm_loop - выходим "жестко"
			exit;
		};
	};
};

sub managing_init {
	my ($this) = @_;

	# begin to handle signals.
	# We do NOT want SA_RESTART in the process manager.
	# -- we want start the shutdown sequence immediately upon SIGTERM.
	unless ($this->no_signals()) {
		sigaction(SIGTERM, $this->{sigaction_no_sa_restart}) or $this->pm_warn("sigaction: SIGTERM: $!");
		sigaction(SIGHUP,  $this->{sigaction_no_sa_restart}) or $this->pm_warn("sigaction: SIGHUP: $!");
		$SIG_CODEREF = sub { $this->sig_manager(@_) };
	}

	# change the name of this process as it appears in ps(1) output.
	$this->{pm_title} = defined $this->{fcgi_main_proc_name} ? $this->{fcgi_main_proc_name} : 'perl-fcgi-pm';
	$this->pm_change_process_name($this->pm_parameter('pm_title'));

	$this->pm_write_pid_file();
};


sub handling_init {
	my $self = shift;
	$self->SUPER::handling_init();

	# change the name of this process as it appears in ps(1) output.
	$self->pm_change_process_name($self->{fcgi_child_proc_name}) if defined $self->{fcgi_child_proc_name};
};

sub pm_die {
	my $self = shift;
	
	$self->{pm_die_flag} = 1;
	
	# вычитываем оцередь сообщений
	my $rcvd;
	while (msgrcv($self->{ipcqueue}, $rcvd, 60, 0, IPC_NOWAIT)) {
	};
	msgctl($self->{ipcqueue}, IPC_RMID, 0);
	
	
	# по оставшемуся списку процессов будет послан сигнал SIGTERM
	# запомним время и изменим статус
	my $time = time();
	foreach my $dpid (keys %{$self->{PIDS}}) {
		#$self->{KILL_PIDS}->{$dpid}->{SIGTERM_TIME} = $time;
		$self->{PIDS}->{$dpid}->{proc_status} = 2;
		$self->{PIDS}->{$dpid}->{SEND_SIG_TIME} = $time;
	};

	#  в случае зависания, ждем 30 секунд
	#$self->{pm_exit_child_timeout} = 120;
	$self->pm_notify("die_timeout = $self->{die_timeout}");

	$self->SUPER::pm_die('Exit by command STOP', 0);
};

sub pm_loop {
	my $self = shift;

	$self->{pm_loop_used} = 1;

	return(!($self->{exit_flag}));
};

sub pm_notify {
	my ($this,$msg) = @_;
	if (defined($msg)) {
		$msg =~ s/\s*$/\n/;
		my $time = POSIX::strftime('%Y-%m-%d %H:%M:%S', localtime(time()));
		print STDERR $time, " - FastCGI: ".$this->role()." (pid $$): ".$msg;
	};
};

1;
