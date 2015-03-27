package Debug;
# модуль для подробной отладки

use strict;
use vars qw(@EXPORT @ISA);
use Data::Dumper;

$|=1;

@ISA	= qw(Exporter); 
@EXPORT = qw(debug);

my $FILE = undef;
sub init {
	my %I = (file=>undef,@_);
	if (defined $I{file} && -w $I{file}){
		$FILE = $I{file};
		return '1';
	}else{
		return "2";
	}
}

sub debug {
	return unless is_on();
	my ($p, $f, $l) = caller(0);
	foreach (@_){
		if (defined $FILE){
			open (LF,">>",$FILE) or die $!;
			print LF localtime()." $$:$p:$f:$l: DBG: ", (ref $_  ? Dumper(@_) : $_), "\n";
			close LF;
		}else{
			print STDERR localtime()." $$:$p:$f:$l: DBG: ", (ref $_  ? Dumper(@_) : $_), "\n";
		}
	}
};

sub is_on {
	return ((exists $ENV{DEBUG} && $ENV{DEBUG} == 1) ? 1 : 0);
}

1;
