package js;

# Библиотека функций для работы с JSON

# to_hash - конвертирует текст в формате JSON в переменную типа HASH
# from_hash - конвертирует переменную типа HASH в текст в формате JSON
# use
# 			21.01.2013 Перевел на JSON::PP

use strict;
use JSON::PP;
use locale;

# Процедура проверки доступа по IP адресу и списку разрешенных IP адресов (с подсетями типа /24, /16 или /8)
# @param text $json
#	текст JSON
# @return HASHREF
#	значение - при нормальном декодировании
#	undef - при проблемах декодирования
sub to_hash {
	my ($json) = @_;
	my $h;
	my $js = JSON::PP->new();
	# позволяет обработать невалидный json
	$js->relaxed(1);
	# преобразование в utf-8
	$js->utf8;
	eval {
		# eval нужен для того что-бы не падало приложение при ошибках обработки json
		$h = $js->decode($json);
	};
	undef($js);
	return($h);
};

# Преобразует hash в json формат
# @param Hash $h
#	<p>набор значений hash</p>
# @param Smallint $pretty
#	<p>выводить красиво</p>
# @param Smallint $utf8convert
#	<p>конвертировать в хеш</p>
# @param Ineteger $bignum
#	<p>использовать bigint</p>
# @return String JSON
#	<p>
#		строка 	- строка, для записи в базу
#		undef 	- не удалось выполнить преобразование
#	</p>
sub from_hash {
	my ($h, $pretty, $utf8convert, $bignum) = @_;

	my $s = '';
	my $js = JSON::PP->new();
	# позволяет обработать невалидный json
	$js->relaxed(1);
	$utf8convert = 1 if !defined $utf8convert;
	if ($utf8convert) {
		# преобразование в utf-8
		$js->utf8;
	}
	$js->pretty(1) if ($pretty);
	if ($bignum) {
		$js->allow_blessed(1);
		$js->allow_bignum(1);
	}
	eval {
		# eval нужен для того что-бы не падало приложение при ошибках обработки json
		$s = $js->encode($h);
	};
	undef($js);

	return($s);
};

1;
