package xml;

# Библиотека функций для работы с XML

# to_hash- Конвертирует xml в hash (без учета аттрибутов)

use strict;
use XML::Hash;

sub to_hash {
	my ($xml) = @_;

	my $xc = XML::Hash->new();
	my $hh = $xc->fromXMLStringtoHash($xml);
	scan_hash($hh);

	# Адаптация для СГ - SELFCARE делаем корневым хэшем
	if (defined($hh->{SELFCARE})) {
		return($hh->{SELFCARE});
	} else {
		return($hh);
	};
};

# Сканируем хэш и элементы с хэшем с одним ключем 'text' заменяем на значение этого ключа
sub scan_hash {
	my ($h) = @_;
	
	my @keys = keys(%{$h});
	if (defined($h->{text}) && ($#keys eq '0')) {
		# Если один ключ text
		return($h->{text});
	} elsif ($#keys < 0) {
		# Пустой хэш - заменяем на пустую строку
		return('');
	} else {
		foreach my $k (@keys) {
			my $v = $h->{$k};
			my $tmp = scan_val($v);
			if (defined($tmp)) {
				$h->{$k} = $tmp;
			};
		};
	};
	return(undef);
};

sub scan_array {
	my ($h) = @_;
	
	my $i = 0;
	while ($i <= $#{$h}) {
		my $v = $h->[$i];
		my $tmp = scan_val($v);
		if (defined($tmp)) {
			$h->[$i] = $tmp;
		};
		$i++;
	};
};

sub scan_val {
	my ($v) = @_;
	
	if (ref($v) eq 'HASH') {
		return(scan_hash($v));
	} elsif (ref($v) eq 'ARRAY') {
		scan_array($v);
	};
	return(undef);
};

1;
