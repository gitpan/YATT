package YATT::LRXML::MetaInfo;
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Class::Configurable);
use YATT::Fields
  (['^nsdict' => sub { {} }]
   , ['cf_namespace' => 'yatt']
   , qw(^=tokens
	cf_filename
      )
   );

sub after_configure {
  my MY $self = shift;
  $self->SUPER::after_configure;
  if (defined $self->{cf_namespace}) {
    my $nsdict = $self->{nsdict} = {};
    $self->{cf_namespace} = [$self->{cf_namespace}]
      unless ref $self->{cf_namespace} eq 'ARRAY';
    foreach my $ns (@{$self->{cf_namespace}}) {
      $nsdict->{$ns} = keys %$nsdict;
    }
  } else {
    $self->{nsdict} = {};
  }
}

sub in_file {
  (my MY $self) = @_;
  if (defined $$self{cf_filename}) {
    " in file $$self{cf_filename}";
  } else {
    '';
  }
}

1;
