package proc;

# Библиотека функций для управления fastcgi демонами

# demonize 			- демонизация процесса
# check_for_one_instance 	- блокировка запуска нескольких экземпляров демона

use strict;
use POSIX;

my $logname;

# Переводит скрипт в режим демона с перенаправлением вывода в указанный лог-файл
# @param text $log
#	полный путь к файлу лога. Если нет - вывод перенаправляется в /dev/null
# @param text $pidfile
#	полный путь к файлу pid
# @return нет
sub demonize {
	my ($log, $pidfile, $opt) = @_;

	fork_proc() && exit 0;

	# Создаем каталог для log-файла
	my $logdir = $log;
	$logdir =~ s/^(.+)\/[^\/]+$/$1/g;
	if (! -d $logdir) {
		system('mkdir -p "'.$logdir.'"');
		system('chmod 777 "'.$logdir.'"');
	};
	$logname = $log;

	# Создаем каталог для pid-файла
	my $piddir = $pidfile;
	$piddir =~ s/^(.+)\/[^\/]+$/$1/g;
	if (! -d $piddir) {
		system('mkdir -p "'.$piddir.'"');
	};

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
		open(STDIN,  ">>".$log) or die "Can't open STDIN: $!";
		open(STDOUT, ">>".$log) or die "Can't open STDOUT: $!";
		open(STDERR, ">>".$log) or die "Can't open STDERR: $!";
	};

	$SIG{USR1} = \&_sig_rotate_logs;
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

# Процедура для обеспечения запуска приложения в единственном экземпляре
sub check_for_one_instance {
	my $cfg = $_[0];
	if ($< ne '0') {
		print STDERR "ERROR: Application possible running only under root user\n";
		exit();
	};

	my ($tmp_log_handle, $tmp_log_name) = (undef, "/tmp/sys_serv_tmp.log");
	open($tmp_log_handle, '>>'.$tmp_log_name);
	print $tmp_log_handle $$." CheckInstance: ".localtime(time)."\n";
	print $tmp_log_handle $$." CheckInstance: begin check...\n";
	open(LOCK, '>'.$cfg->{lock_file}) if (defined($cfg->{lock_file}) && ($cfg->{lock_file} ne ''));
	# Установить блокировку файла (LOCK_SH, LOCK_EX - 1,2)
	# Можно воспользоваться библиотекой: use Fcntl ':flock';
	flock(LOCK, 2) if (defined($cfg->{lock_file}) && ($cfg->{lock_file} ne ''));
	# Прочитать pid процесса из файла, запущенных процессов
	if ( -e $cfg->{pid_file} ) {
		open(FL, '<'.$cfg->{pid_file});
		my $pid = <FL>;
		print $tmp_log_handle $$." CheckInstance: there is Pid file with PID=".$pid."\n";
		close(FL);
		#my $cmd = "/bin/ps -A|grep -E \"^[^0-9]*".$pid."\"|awk '{print \$1}'";
		my $cmd = "/bin/ps h -p ".$pid." -o pid";
		my $pidstr = `$cmd`;
		chomp($pidstr);
		if ($pidstr =~ /^\s*(\d+)\s*/) {
			$pidstr = $1;
		};
		print $tmp_log_handle $$." CheckInstance: Run ps command and get result: ".$pidstr."\n";
		# Если процесс запущен - отказать в запуске
		if ($pid eq $pidstr) {
			print $tmp_log_handle $$." CheckInstance: Process with ID=".$pid." is already running\n";
			print STDERR "ERROR: Application already running (pid:", $pid, ")\n";
			print $tmp_log_handle $$." CheckInstance: end check...\n\n";
			close($tmp_log_handle);
			exit();
		} else {
			# Если процесс не запущен, установить новый pid в файл процесса
			print $tmp_log_handle $$." CheckInstance: no any running process, start new...\n";
			open(FL, '>'.$cfg->{pid_file});
			print FL $$;
			close(FL);
		};
	};
	print $tmp_log_handle $$." CheckInstance: end check...\n\n";
	close($tmp_log_handle);
	# Снять блокировку с файла (константы LOCK_UN - 4 или 8)
	flock(LOCK,8) if (defined($cfg->{lock_file}) && ($cfg->{lock_file} ne ''));
	close(LOCK) if (defined($cfg->{lock_file}) && ($cfg->{lock_file} ne ''));
};

# Если в командной строке последним параметром идет команда "restart" или "stop" - выполняем ее через SHARED_UTILS/checker_fcgi.pl
sub check_command {
	my ($cfgname) = @_;

	if (($#ARGV >= 0) && (($ARGV[$#ARGV] eq 'restart') || ($ARGV[$#ARGV] eq 'stop'))) {
		my $S = '/home/projects/SHARED_UTILS/checker_fcgi.pl "'.$cfgname.'" '.$ARGV[$#ARGV];
		exec($S);
		exit;
	} elsif (($#ARGV >= 0) && ($ARGV[$#ARGV] eq 'check')) {
		my $S = '/home/projects/SHARED_UTILS/checker_fcgi.pl "'.$cfgname.'"';
		exec($S);
		exit;
	};
};

sub _sig_rotate_logs {
	if (defined($logname)) {
		close(STDIN); open(STDIN,  ">>".$logname);
		close(STDOUT); open(STDOUT, ">>".$logname);
		close(STDERR); open(STDERR, ">>".$logname);
	};
};

1;
