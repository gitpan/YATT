package YATT::Class::ArrayScanner;
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Class::Configurable);
use YATT::Fields qw(^cf_array cf_index);

sub readable {
  (my MY $path, my ($more)) = @_;
  return unless defined $path->{cf_index};
  $path->{cf_index} + ($more || 0) < @{$path->{cf_array}};
}

sub read {
  (my MY $path) = @_;
  return undef unless defined $path->{cf_index};
  my $value = $path->{cf_array}->[$path->{cf_index}];
  $path->after_read($path->{cf_index}++);
  $value;
}

sub after_read {}

sub current {
  (my MY $path, my ($offset)) = @_;
  return undef unless defined $path->{cf_index};
  $path->{cf_array}->[$path->{cf_index} + ($offset || 0)]
}

sub next {
  (my MY $path) = @_;
  return undef unless defined $path->{cf_index};
  $path->{cf_array}->[$path->{cf_index}++];
}

1;
