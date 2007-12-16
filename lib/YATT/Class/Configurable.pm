# -*- mode: perl; coding: utf-8 -*-
package YATT::Class::Configurable;
use strict;
use warnings FATAL => qw(all);
use fields;
sub MY () {__PACKAGE__}

sub new {
  my MY $self = fields::new(shift);
  $self->before_configure;
  if (@_) {
    $self->init(@_);
  } else {
    $self->after_configure;
  }
  $self
}

sub initargs {return}

sub init {
  my MY $self = shift;
  if (my @member = $self->initargs) {
    @{$self}{@member} = splice @_, 0, scalar @member;
  }
  if (@_) {
    $self->configure(@_);
  } else {
    $self->after_configure;
  }
  $self;
}

sub clone {
  my MY $ref = shift;
  ref($ref)->new(map($ref->{$_}, $ref->initargs)
		 , $ref->configure
		 , @_);
}

sub cget {
  (my MY $self, my ($cf)) = @_;
  $self->{"cf_$cf"};
}

sub before_configure {}

sub configure {
  my MY $self = shift;
  unless (@_) {
    # list all configurable options.
    return sort map {
      if (m/^cf_(.*)/) {
	$1
      } else {
	()
      }
    } keys %$self;
  }
  if (@_ == 1) {
    return $self->{"cf_$_[0]"};
  }
  die "Odd number of arguments" if @_ % 2;

  my @task;
  while (my ($name, $value) = splice @_, 0, 2) {
    if (my $sub = $self->can("configure_$name")) {
      push @task, [$sub, $value];
    } else {
      $self->{"cf_$name"} = $value;
    }
  }
  foreach my $task (@task) {
    $task->[0]->($self, $task->[1]);
  }
  $self->after_configure;
  $self;
}

sub after_configure {
  my MY $self = shift;
  # $self->SUPER::after_configure;
  foreach my $cf (grep {/^cf_/} keys %$self) {
    next if defined $self->{$cf};
    my $sub = $self->can("default_$cf") or next;
    $self->{$cf} = $sub->();
  }
}
1;
