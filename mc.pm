package mc;

# Библиотека функций для работы с memcached
# check_memc_connect - процедура контроля соединения к серверу memcached
# set
# get

use strict;
use Cache::Memcached;
use POSIX;
use utf8;
use Encode;
use LWP;
use Time::HiRes qw(time);

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
		$memc->set('test_flag', 'test_flag_value');
		$flg = $memc->get('test_flag');
	};
	if (!defined($flg) || ($flg eq '') || ($flg ne 'test_flag_value')) {
		if (defined($servers)) {
			if (ref($servers) eq 'ARRAY') {
				$memc = Cache::Memcached->new( { 'servers' => $servers,
						'namespace' => $namespace,
						'compress_threshold' => 1000, } );
			} else {
				$memc = Cache::Memcached->new( { 'servers' => [ $servers ],
						'namespace' => $namespace,
						'compress_threshold' => 1000, } );
#				open(FL, '>>/var/log/projects/memcache.log');
#				print FL "WARNING: Use old style memcached config: ", $0, "\n";
#				close(FL);
			};
			# Проверка подключения к серверу(ам) memecached
			$memc->set('testval'.$$, 'test_flag_value2',60);
			my $testvalmemc = $memc->get('testval'.$$);
#			open(FL, '>>/var/log/projects/memcache.log');
#			print FL "WARNING: |".'testval'.$$."| - |$testvalmemc| \n";
#			close(FL);

			if ((!defined $testvalmemc) ||($testvalmemc ne 'test_flag_value2')) {
				return undef;
			};
		};
	};
	return($memc);
};

# Записывает значение по ключу
# @param Memcached $memc
#	<p>Соединение к memcached серверу</p>
# @param String $prefix
#	<p>Префикс для заданного приложения. Он же namespace</p>
# @param String $id
#	<p>Ключ значения</p>
# @param String $val
#	<p>Значение</p>
# @param String $ttl
#	<p>Время жизни до сброса значения в кеше</p>
# @return String
#	<p>
#		указатель 	- указатель на ячейку
#		undef 		- не удалось выполнить операцию записи значения в кеш
#	</p>
sub set {
	my ($memc, $prefix, $id, $val, $ttl) = @_;
	# @todo - дополнить функционалом: время изменения записи в memcached
	if (!defined $id) {$id = '';};

	if (defined($memc) && defined($val)) {
		# Устанавливаем актуальное время для значения
		$memc->set('__atime__::'.$prefix.$id, time(), $ttl);
		return($memc->set($prefix.$id, $val, $ttl));
	} else {
		return(undef);
	};
}

# Получает значение по ключу
# @param Memcached $m3emc
#	<p>Соединение к memcached серверу</p>
# @param String $prefix
#	<p>Префикс для заданного приложения. Он же namespace</p>
# @param String $id
#	<p>Ключ значения</p>
# @return String
#	<p>
#		значение 	- значение в ячейке
#		undef 		- не удалось выполнить операцию записи значения в кеш
#	</p>
sub get {
	my ($memc, $prefix, $id) = @_;
	if (!defined $id) {$id = '';};
	# @todo - дополнить функционалом: время изменения записи в memcached
	if (defined($memc)) {
		# Сначала проверяем что актуалье время значения позже чем актуальное время для группы
		my $gtime = $memc->get('__atime__::'.$prefix);
		if (defined($gtime) && ($gtime ne '')) {
			my $vtime = $memc->get('__atime__::'.$prefix.$id);
			if (defined($vtime) && ($vtime ne '') && ($vtime <= $gtime)) {
				return(undef);
			};
		};
		return($memc->get($prefix.$id));
	} else {
		return(undef);
	};
};

sub delete {
	my ($memc, $prefix, $id) = @_;
	if (defined($memc)) {
		$memc->delete('__atime__::'.$prefix.$id);
		return($memc->delete($prefix.$id));
	} else {
		return(undef);
	};
};

sub inc {
	my ($memc, $prefix, $id, $val) = @_;
	# @todo - дополнить функционалом: время изменения записи в memcached
	if (defined($memc)) {
		# Устанавливаем актуальное время для значения
		$memc->set('__atime__::'.$prefix.$id, time());
		$val = 1 if (!defined($val));
		return($memc->incr($prefix.$id, $val));
	} else {
		return(undef);
	};
}

# Ресет группы значений
sub reset {
	my ($memc, $prefix) = @_;
	if (defined($memc) && defined($prefix)) {
		return($memc->set('__atime__::'.$prefix, time()));
	} else {
		return(undef);
	};
};


1;
