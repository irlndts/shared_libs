package disk;

# @tutorial Работа с файловой системой на том хсоет, где запущен скрипт
#	DAC (Discretionary Access Control)
#	MAC (Mandatory Access Control)
#	ACL (Access Control List)
# @since
#	0.1
#		Анализ дирректории с целью выяснить установленные права на все файлы и каталоги внутри

use POSIX;
use utf8;
use strict;


# @tutorial Анализирует дирректорию. Составляет карту прав на каждый файл и дирректорию внутри указанного файла
# @params String $path
#	<p>
#		абсолютный путь к дирректории. Default "/"
#	<p>
# @params Boolean $recursive
#	<p>
#		обойти все вложенные каталоги. Default false
#	<p>
# @return
#	<p>
#		hash - хеш всех дирректорий и файлов внутри с правами доступа
#	</p>
sub getFilePermissions {
	# Получение параметров
	my $path		= shift;
	my $recursive	= shift;

	# Начальное объявление
	my $output		= {};
	my ($info,$command) = ();

	if ((defined $recursive)&&($recursive eq 'true')) {
		$command = 'ls -lpFRAB';
	} else {
		$command = 'ls -lpFAB';
	}

	if (defined $path) {
		$command .= ' '.$path;
	} else {
		$command .= '/';
	}

	$info = `$command`;
	my @lines = split /\n/,$info;
	my $lastDIR;
	my $next = undef;
	LINES: for(my $i=0;$i<scalar(@lines);$i++) {
		if ($lines[$i] =~ /^([a-zA-Z0-9\/]+)\:/) {
			$lastDIR = $1;
			$lastDIR =~ s/$path//;
			# Удаление каталогов, начинающихся с .
			if ($lastDIR =~ /^\/*\.([a-zA-Z0-9\/]+)\:/) {
				$next = 1;
			} else {
				$next = undef;
			}
			next(LINES);
		}

		if (defined $next) {next(LINES);}

		my @element = split /\s+/,$lines[$i];
		my $count = scalar(@element)-1;
		if ($element[$count] =~ /^\/*\.([a-zA-Z0-9\-\_]+)/) {next(LINES);}

		if ((defined $element[$count])&&($count >=6)) {
			if ((defined $lastDIR) &&($lastDIR ne '')) {
				$element[$count] = $lastDIR."/".$element[$count];
			}
			$output->{$element[$count]} = {};

			if ($element[0] =~ /^d([\w\-]+)/) {
				$output->{$element[$count]}->{rights} = $1;
			} else {
				if ($element[0] =~ /^\-([\w\-]+)/) {
					$output->{$element[$count]}->{rights} = $1;
				} else {
					$output->{$element[$count]}->{rights} = $element[0];
				}
			}
			$output->{$element[$count]}->{user} 		= $element[2];
			$output->{$element[$count]}->{group}		= $element[3];
		}
	}

	return $output;
}

# @tutorial Находит отличие в правах на файлы в двух дирректориях
# @params String $path1
#	<p>
#		абсолютный путь к дирректории. Default "/"
#	<p>
# @params String $path2
#	<p>
#		абсолютный путь к дирректории2. Default undef
#	<p>
# @params Boolean $recursive
#	<p>
#		обойти все вложенные каталоги дял двух дирреткорий. Default false
#	<p>
# @return
#	<p>
#		undef - ошибка выполнения
#		hash - хеш всех дирректорий и файлов внутри с правами доступа
#	</p>
sub getFilePermissionsDif {
	# Получение параметров
	my $path1		= shift;
	my $path2		= shift;
	my $recursive	= shift;

	# Начальное объявление
	my $output		= {};
	my ($elements1,$elements2) = ();

	$elements1 = disk::getFilePermissions($path1,$recursive);
	$elements2 = disk::getFilePermissions($path2,$recursive);

	if (abs(keys(%{$elements1})-keys(%{$elements2}))>keys(%{$elements1})*4/5) {
		return undef;
	} else {
		foreach my $element (keys %{$elements1}) {
			if (defined $elements2->{$element}) {
				if (($elements2->{$element}->{rights} ne $elements1->{$element}->{rights}) || ($elements2->{$element}->{user} ne $elements1->{$element}->{user}) || ($elements2->{$element}->{group} ne $elements1->{$element}->{group})) {
					$output->{$element} = {};
					$output->{$element}->{file1} = $elements1->{$element};
					$output->{$element}->{file2} = $elements2->{$element};
				}
			}
		}
	}

	return $output;
}

1;