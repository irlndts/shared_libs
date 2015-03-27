package Timer;
# простой замер времени выполнения операций.

use strict;
use vars qw(@ISA @EXPORT);
use locale;
use Time::HiRes qw/time/;
use Exporter;

@ISA = qw(Exporter);
@EXPORT = qw/tic toc tictoc tic_clear average/;

my %_TICTOC = ();

=nd
Начать замер.
=cut

sub tic {
	my $key = shift;
	$_TICTOC{$key} = {SUM=>0} unless exists $_TICTOC{$key};
	$_TICTOC{$key}->{start} = time;
	$_TICTOC{$key}->{count}++ if exists $_TICTOC{$key};
}

=nd
Остановить замер
=cut

sub toc {
	my $key = shift;
	if ((defined $_TICTOC{$key})&&(defined $_TICTOC{$key}->{start})) {
		$_TICTOC{$key}->{SUM} += time - $_TICTOC{$key}->{start};
	}
	$_TICTOC{$key}->{start} = 0;
}

=nd
Показать результат
=cut

sub tictoc {
	my $key = shift;
	return (exists $_TICTOC{$key} ? $_TICTOC{$key}->{SUM} : 0);
}

=nd
Очистить таймер
=cut

sub tic_clear {
	my $key = shift;
	unless ($key){
		%_TICTOC = ();
		return 1;
	}
	return delete $_TICTOC{$key};
}

=nd
Усреднить показания. Время/количество замеров по ключу.
=cut
sub average {
	my $key = shift;
	return (exists $_TICTOC{$key} ? $_TICTOC{$key}->{SUM}/$_TICTOC{$key}->{count} : 0);
}

1;
