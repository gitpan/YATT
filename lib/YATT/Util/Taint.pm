# -*- mode: perl; coding: utf-8 -*-
package YATT::Util::Taint;
use base qw(Exporter);
use strict;

BEGIN {
  our @EXPORT_OK = qw(&untaint_any &tainted &is_tainted);
  our @EXPORT    = @EXPORT_OK;
}

use Scalar::Util qw(tainted);

sub untaint_any {
  $1 if defined $_[0] && $_[0] =~ m{(.*)}s;
}

sub is_tainted {
  return not eval { eval("#" . substr(join("", @_), 0, 0)); 1 };
}

1;
