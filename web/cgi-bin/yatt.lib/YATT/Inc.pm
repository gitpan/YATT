# -*- mode: perl; coding: utf-8 -*-
package YATT::Inc;
use strict;
use warnings FATAL => qw(all);

sub import {
  __PACKAGE__->add_inc(caller);
}

sub add_inc {
  my ($pack, $callpack) = @_;
  $callpack =~ s{::}{/}g;
  $INC{$callpack . '.pm'} = 1;
}

1;
