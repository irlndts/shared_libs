package ip;

# Библиотека функций связанных с работой с TCP/IP

# check_ip_access 		- процедура проверки доступа по IP адресу и списку разрешенных IP адресов (с подсетями типа /24, /16 или /8)

use strict;
use POSIX;

# Процедура проверки доступа по IP адресу и списку разрешенных IP адресов (с подсетями типа /24, /16 или /8)
# @param text $iplist
#	список разрешенных IP через запятую
# @param text $ip
#	проверяемый IP
# @return int
#	1 - если доступ разрешен
#	0 - если доступ запрещен
sub check_ip_access {
	my ($iplist, $ip, $option1) = @_;

	# Список адресов могут быть перечислены через запятую
	my @ipl = split(/\,/, $iplist);

	my $access = 0;
	# Перебираем все ip адреса
	foreach my $ipr (@ipl) {
		# Опции могут идти за адресом разделенные через |
		if ($ipr =~ /^([^\|]+)\|(.+)$/) {
			# Проверка на совпадение с нужным ip адресом
			if ($1 eq $ip) {
				my @options = split(/\|/, $2);
				# Проверка на совпадение первой опции (пока только одной)
				if (defined($options[0])) {
					if ($options[0] eq $option1) {
						return(1);
					};
				};
			};
		} elsif ($ipr =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)\/(\d+)$/) {
			# Подсеть
			my $l = int($5/8);
			my @ipa = split(/\./, $ip);
			my @net = ($1, $2, $3, $4);

			my $i = 0;
			my $a = 1;
			# Проверка совпадений
			while ($i < $l) {
				if ($ipa[$i] ne $net[$i]) {
					$a = 0;
				};
				$i++;
			};
			if ($a == 1) {
				return(1);
			};
		} else {
			return(1) if ($ipr eq $ip);
		};
	};
	return(0);
};

1;
