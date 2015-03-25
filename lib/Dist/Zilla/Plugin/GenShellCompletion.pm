package Dist::Zilla::Plugin::GenShellCompletion;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use utf8;

use Moose;
use namespace::autoclean;

use List::Util qw(first);

with (
    'Dist::Zilla::Role::BeforeBuild',
    'Dist::Zilla::Role::InstallTool',
    'Dist::Zilla::Role::FileFinderUser' => {
        default_finders => [':ExecFiles'],
    },
);

sub before_build {
    my $self = shift;

    unless (@{ $self->found_files }) {
        return;
    }

    $self->zilla->register_prereqs({phase => 'configure'}, 'Perl::osnames' => '0.09');
}

sub setup_installer {
  my ($self) = @_;

  unless (@{ $self->found_files }) {
      $self->log_debug('No scripts in this distribution, skipped');
      return;
  }

  # first, try MakeMaker
  my $build_script = first { $_->name eq 'Makefile.PL' }
      @{ $self->zilla->files };
  $self->log_fatal('No Makefile.PL found. Using [MakeMaker] is required')
      unless $build_script;

  my $content = $build_script->content;

  no strict 'refs';
  my $header = "
# modify generated Makefile to generate shell completion scripts. this piece\n".
"# is generated by " . __PACKAGE__ . " version " .
    (${__PACKAGE__ ."::VERSION"} // 'dev').".\n";

  my $body = <<'_';
GEN_SHELL_COMPLETION:
{
    require Perl::osnames;
    last unless Perl::osnames::is_posix();

    print "Modifying Makefile to generate shell completion on install\n";
    open my($fh), "<", "Makefile" or die "Can't open generated Makefile: $!";
    my $content = do { local $/; ~~<$fh> };

    $content =~ s/^(install :: pure_install doc_install)/$1 comp_install/m
        or die "Can't find pattern in Makefile (1)";

    $content =~ s/^(uninstall :: .+)/$1 comp_uninstall/m
        or die "Can't find pattern in Makefile (2)";

    $content .= qq|\ncomp_install :\n\t| .
        q|$(PERLRUN) -E'if(eval { require App::shcompgen; 1 }) { system "shcompgen", "--verbose", "generate", "--replace", @ARGV }' -- $(EXE_FILES)| .
        qq|\n\n|;

    $content .= qq|\ncomp_uninstall :\n\t| .
        q|$(PERLRUN) -E'if(eval { require App::shcompgen; 1 }) { system "shcompgen", "--verbose", "remove", @ARGV }' -- $(EXE_FILES)| .
        qq|\n\n|;

    open $fh, ">", "Makefile" or die "Can't write modified Makefile: $!";
    print $fh $content;
}
_

  $content .= $header . $body;

  return $build_script->content($content);
}

no Moose;
1;
# ABSTRACT: Generate shell completion scripts when distribution is installed

=for Pod::Coverage setup_installer before_build

=head1 SYNOPSIS

In your dist.ini:

 [GenShellCompletion]


=head1 DESCRIPTION

This plugin modifies C<Makefile.PL> so that when a user installs your
distribution with C<make install>, L<shcompgen> is invoked to generate shell
completion scripts for your scripts. This is convenient because immediately
after the user installs your distribution, shell tab completion is already
activated for your scripts.

L<shcompgen> recognizes several ways/hints to generate completion to your
scripts. Please see its documentation for more details.

Some notes:

First, user must already install and setup L<shcompgen> prior to installing your
distribution. But if C<shcompgen> is installed after your distribution is
installed, she can simply run C<shcompgen generate> to scan PATH and generate
completion for all recognized programs, including yours.

Second, this plugin's implementation strategy is currently as follow (probably
hackish): insert some code in the generated C<Makefile.PL> after
C<WriteMakefile()> to insert some targets in the C<Makefile> generated by
C<Makefile.PL>.

Third, currently only MakeMaker is supported, L<Module::Build> is not.


=head1 SEE ALSO

L<shcompgen>

CLI scripts using the L<Perinci::CmdLine> framework will automatically have
shell tab completion capability. C<shcompgen> detects this.

You can also use L<Getopt::Long::Complete> or L<Getopt::Long::Subcommand>.
C<shcompgen> also detects this.

=cut
