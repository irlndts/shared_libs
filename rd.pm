package rd;

# Библиотека функций для работы с Redis

# check_redis_connect 		- процедура контроля соединения к серверу Redis

use strict;
use Redis;
use POSIX;

# Процедура контроля соединения к серверу Redis
# @param Redis $redis
#	коннект к серверу Redis
# @param text $server
#	сервер для подключения в виде "ip:port"
# @return DBI
#	Если соединение в порядке, возвращает тот-же Redis, который был в параметре $redis
#	Если соединение разорвано, формируется новый коннект и возвращается новый объект Redis
#	Если соединение не было установлено - возвращается undef
sub check_redis_connect {
	my ($redis, $server) = @_;
	
	my $flg;
	if (defined($redis) && ($redis->ping())) {
		$redis->set('test_flag', 1);
		$flg = $redis->get('test_flag');
	};
	if (!defined($flg) || ($flg eq '')) {
		if (defined($server)) {
			$redis = Redis->new( server => $server );
			
			# Проверка подключения к серверу(ам) memecached
			$redis->set('test_flag2', 123);
			my $testvalredis = $redis->get('test_flag2');
			if ((!defined $testvalredis) ||(123 ne $testvalredis)){
				return undef;
			};
		};
	};
	return($redis);
};

# Процедура соединения к серверу Redis, с обработкой ошибки соединения с сервером
# возвращает undef в случае если подключение в данный момент невозможно:
sub redis_reconnect {
	my $redis = shift;
	if (defined $redis){
		# имеется соединение, проверяем его работоспособность:
		unless ($redis->ping){
			# пытаемся пересоединиться:
			$redis = redis_eval_connect(@_);
		}
	}else{
		$redis = redis_eval_connect(@_);
	}
	return $redis;
}

# сделать соединение к редису 
sub redis_eval_connect {
	my $r = undef;
	eval{$r = new Redis(@_);};
	warn $@ if $@;
	return $r;
}

1;
