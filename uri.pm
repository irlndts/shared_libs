package uri;

# @tutorial Class функции для работы с ссылками
# @version 0.1
# @copyright cqspel 21.09.2012
# @since
#	0.1
#		getRequestParams Получение списка переданных парамтеров
#		parseParamsString Парсит сроку с парамтерами запроса и правильным обращом формируте хеш параметров

use strict;
use POSIX;
use URI::Escape;

# Процедура проверки доступа по IP адресу и списку разрешенных IP адресов (с подсетями типа /24, /16 или /8)
# @param text $queryString
#	строка запроса (парметры из get запроса). Обычно $ENV{QUERY_STRING}
# @param text $POSTDATA
#	данные, переданные постом
# @param hash $HEADER_BLOCKS
#	список конкретных разделов их заголовка, которые необходимо получить
#	в случае, если переменная не задана, используются все переменные из заголовка 
# @return hash
#	hash - если парамтеры получены
#	undef - если парамтеры не были переданы
sub getRequestParams {
	my ($params,$queryString, $POSTDATA,$HEADER_BLOCKS) = @_;
#	open("F",">/tmp/cqspel.txt");
	$queryString 	= uri_unescape($queryString);
	$POSTDATA 		= uri_unescape($POSTDATA);
	# Выходной массив
	my $return = {};
	# Если был передан блок с парамтерами, учесть их в парсинге
	if (defined $params) {
		$return = $params;
#		print F "Найдены параметры\n";
	}

	# Анализ queryString
	if ((defined $queryString)&&($queryString ne '')) {
#		print F "Найдены get параметры: $queryString\n";
		$return = &parseParamsString($return,$queryString);
	}
	# Анализ POST данных
	if ((defined $POSTDATA)&&($POSTDATA ne '')) {
#		print F "Найдены post параметры: $POSTDATA\n";
		$return = &parseParamsString($return,$POSTDATA);
	}
	# Анализ параметров из заголовков
	if ((defined $HEADER_BLOCKS)&&(keys %{$HEADER_BLOCKS} >0)) {
		foreach my $key (keys %{$HEADER_BLOCKS}) {
			if (defined $ENV{$HEADER_BLOCKS->{$key}}) {
				$return = &parseParamsString($return,$ENV{$HEADER_BLOCKS->{$key}});
			}
		}
	}
#	foreach my $key (keys %{$return}) {
#		print F "$key = ".$return->{$key}."\n";
#		if ((defined $return->{$key})&&(!ref $return->{$key})) {
#			print F "$key = ".$return->{$key}."\n";
#		} elsif ((defined $return->{$key})&&(ref $return->{$key} eq 'ARRAY')) {
#			print F "Array found \n";
#			for (my $i=0;$i<@{$return->{$key}};$i++){
#				print F "\t".$return->{$key}->[$i]."\n";
#			}
#		} elsif (defined $return->{$key}) {
#			print F ref($return->{$key})."\n";
#		}
#	}
#	close(F);
	return $return;
};

# Процедура проверки доступа по IP адресу и списку разрешенных IP адресов (с подсетями типа /24, /16 или /8)
# @param hash $params
#	хеш парамтеров ввода
# @param text $string
#	строка с параметрами
# @param hash $HEADER_BLOCKS
#	список конкретных разделов их заголовка, которые необходимо получить
#	в случае, если переменная не задана, используются все переменные из заголовка 
# @return hash
#	hash - если парамтеры получены
sub parseParamsString {
	my ($params, $string) = @_;
	my @paramValue = split /&/, $string;
	foreach my $env (@paramValue) {
		my ($key, $val) = split /=/, $env, 2;
#		$val =~ s/^"//;
#		$val =~ s/"$//;
		$val =~ s/--//g;
		# Заменить элемент на массив
		if ((defined $params->{$key})&&(!ref $params->{$key})) {
			my $array = ();
			push @{$array}, $params->{$key};
			push @{$array}, $val;
			$params->{$key} = ();
			$params->{$key} = $array;
		} elsif ((defined $params->{$key})&&(ref $params->{$key} eq 'ARRAY')) {
			# Если массив, то просто дописать в нег онудное значение
			push @{$params->{$key}}, $val;
		} else {
			$params->{$key} = $val;
		}
	}
	return $params;
};

# @tutorial Канонизация параметров
# @param varchar $param
#	Значение нового парамтера
# @return varchar
#	приведенное значение входного параметра
sub canonizeHTTPParams {
	my $param = shift;
	if (!defined $param) {return undef;} else {
		$_ = $param;
		s/--//g;
		s/[\n\r]+//g;
		s/^\s+//g;
		s/\s+$//g;
		s/\"//g;
		return $_;
	}
}
1;