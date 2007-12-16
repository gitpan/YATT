package YATT::LRXML;
use strict;
use warnings FATAL => qw(all);

use YATT::Util qw(require_and);

sub Parser () { 'YATT::LRXML::Parser' }

# Returns YATT::LRXML::Cursor
sub read_string {
  my $pack = shift;
  my $parser = require_and($pack->Parser, 'new');
  $parser->parse_string(@_);
}

#========================================

package YATT::LRXML::Scanner; # To scan tokens.
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Class::ArrayScanner);
use YATT::Fields qw(cf_path cf_linenum cf_metainfo);

sub expect {
  (my MY $path, my ($patterns)) = @_;
  return unless $path->readable;
  my $value = $path->{cf_array}[$path->{cf_index}];
  my @match;
  foreach my $desc (@$patterns) {
    my ($toktype, $pat) = @$desc;
    next unless @match = $value =~ $pat;
    $path->after_read($path->{cf_index}++);
    return ($toktype, @match);
  }
  return;
}

sub after_read {
  (my MY $path, my ($pos, $mag)) = @_;
  unless (defined $$path{cf_linenum}) {
    $$path{cf_linenum} = 1;
  } elsif ($pos - 1 >= 0) {
    $mag = 1 unless defined $mag;
    $$path{cf_linenum} += $mag * $path->{cf_array}[$pos - 1] =~ tr:\n::;
  } else {
    # nop.
  }
}

sub error {
  (my MY $self, my ($mesg)) = @_;
  $mesg .= $self->{cf_metainfo}->in_file;
  "$mesg at line $self->{cf_linenum}";
}

#========================================
package YATT::LRXML::Builder; # To build tree.
use strict;
use warnings FATAL => qw(all);
use base qw(YATT::Class::Configurable);
use YATT::Fields qw(^product ^parent ^is_switched
		    cf_endtag cf_startpos cf_startline);

sub initargs {qw(product parent)}

sub new {
  my $pack = shift;
  my MY $path = $pack->SUPER::new;
  $path->init(@_) if @_;
  $path;
}

sub init {
  my MY $path = shift;
  @{$path}{qw(product parent)} = splice @_, 0, 2;
  $path->configure(@_) if @_;
  $path;
}

sub verify_close {
  (my MY $self, my ($tagname, $scan)) = @_;
  unless (defined $self->{cf_endtag}) {
    die $self->error("TAG: /$tagname without open");
  }
  unless ($tagname eq $self->{cf_endtag}) {
    die $self->error("TAG: " . $scan->peek($self->{cf_startpos})
		     . " at line " . $self->{cf_startline}
		     ." closed by /$tagname");
  }
}

sub add {
  my MY $self = shift;
  push @{$self->{product}}, @_;
  $self;
}

sub switch {
  (my MY $self, my ($elem)) = @_;
  unless ($self->{is_switched}) {
    $self->{is_switched} = $self->{product};
  }
  push @{$self->{is_switched}}, $elem;
  $self->{product} = $elem;
  $self;
}

1;
