package js;

# Библиотека функций для работы с JSON

# to_hash - конвертирует текст в формате JSON в переменную типа HASH
# from_hash - конвертирует переменную типа HASH в текст в формате JSON
# use
# 			21.01.2013 Перевел на JSON::PP

use strict;
use JSON::PP;
use locale;

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
