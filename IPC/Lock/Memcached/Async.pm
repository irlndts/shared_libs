package IPC::Lock::Memcached::Async;
use base IPC::Lock::Memcached;

sub DESTROY {
    my $self = shift;
};

1;
