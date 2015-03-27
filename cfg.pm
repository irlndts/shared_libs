package cfg;

# Библиотека функций для работы с конфигами
# parseConfig	- разбор конфига и запись его в хэш

use strict;

# Считывает конфигурационные файлы и формирует ссылку на хэш с параметрами из него
# @param text @files
#	список имен конфигурационных файлов (полный путь)
# @return hashref
#	ссылка на хэш с параметрами из всех указанных конфигурационных файлов
#	если в нескольких файлах есть одинаковые имена параметров, установится значение из последнего
sub parseConfig {
	my $cfg = {};

	my $cnt = 0;
	while (my $cfgfile = shift) {
		$cnt++;
		if ( -e $cfgfile ) {
			open(CFG, '<'.$cfgfile);
			while (<CFG>) {
				$_ =~ s/\#.*//gi;		# Удаляем комментарии
				$_ =~ s/^\s+//gi;		# Начальные пробелы
				$_ =~ s/\s+$//gi;		# Завершающие пробелы

				if ($_ =~ /^([a-zA-Z0-9\_]+)\=(.*)$/) {
					my $v = $2;
					my $ky = $1;
					$v =~ s/^\"//gi;
					$v =~ s/\"$//gi;
					# Обработка true, false
					if($v =~ /^true$/i){
						$cfg->{$ky} = 1;
					} elsif ($v =~ /^false$/i){
						$cfg->{$ky} = 0;
					}
					$cfg->{$ky} = $v;
				};
			};
			close(CFG);
		} else {
			print STDERR "ERROR: Can not found config file: ", $cfgfile, "\n";
			return undef;
		};
	};
	if ($cnt <= 0) {
		print STDERR "ERROR: Lost config file name\n";
		return undef;
	};

	# Формируем массив memcached подключений из переменных типа memcNNN_host и memcNNN_port
	my $htmp = {};
	# Сформировать массив для рекламмы
	my $advert = {};
	foreach my $k (keys %{$cfg}) {
		if ($k =~ /^memc([0-9]+)\_host/) {
			$htmp->{$1}->{host} = $cfg->{$k};
		} elsif ($k =~ /^memc([0-9]+)\_port/) {
			$htmp->{$1}->{port} = $cfg->{$k};
		} elsif ($k =~ /^advert\_([0-9]+)\_([0-9A-Za-z\_\-\.]+)/) {
			$advert->{$1}->{$2} = $cfg->{$k};
		}
	};

	$cfg->{memc_servers} = ();
	my $sep = '';
	foreach my $k (sort(keys %{$htmp})) {
		push(@{$cfg->{memc_servers}}, $htmp->{$k}->{host}.':'.$htmp->{$k}->{port});
	};

	# Сформировать массив хешей
	$cfg->{advert} = ();
	foreach my $k (sort(keys %{$advert})) {
		my $tmp = {};
		foreach my $l (sort(keys %{$advert->{$k}})) {
			$tmp->{$l} = $advert->{$k}->{$l};
		}
		push(@{$cfg->{advert}}, $tmp);
	};

	return($cfg);
};


# Считывает ини файл с конфигом
# @param String $fileName
# <p>
#	Имя файла конфигурации
# </p>
# @param String $method
# <p>
#	tie		- возращает hash (преоразует класс в переменную)
#	link	- возвращает ссылку на hash
# </p>
# @return Hash
#	<p>
#		undef 	- не удалось выполнить чтение ini файла
#		hash 	- Создает хеш из значений конфига
#	</p>
sub readINI {
	my $fileName 	= shift;
	my $method 		= shift;
	# Прочитать файл конфига
	my %iniHash = undef;
	my $iniLink = undef;
	if (!defined $fileName) {
			if ((defined $method) &&($method eq 'tie')) {
				tie %iniHash, 'Config::IniFiles', ( -file => "./configure.ini");
			} else {
				$iniLink = Config::IniFiles->new( -file => "./configure.ini");
			}
	} else {
		if ((defined $method) &&($method eq 'tie')) {
			tie %iniHash, 'Config::IniFiles', ( -file => $fileName);
		} else {
			$iniLink = Config::IniFiles->new( -file => $fileName);
		}
	}

	if (defined $iniHash{system}){
		# Проверка считанных данных
		if (!defined $iniHash{system}{active}) {
			return undef;
		}
		return %iniHash;
	} elsif (defined $iniLink) {
		# Проверка считанных данных
		if (!defined $iniLink->{system}->{active}) {
			return undef;
		}
		return $iniLink;
	} else {
		return undef;
	}
}

1;