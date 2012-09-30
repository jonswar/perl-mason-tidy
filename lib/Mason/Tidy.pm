package Mason::Tidy;
use File::Slurp;
use Getopt::Long qw(GetOptionsFromArray);
use Method::Signatures::Simple;
use Moo;
use Perl::Tidy qw();
use strict;
use warnings;

my $marker_count = 0;

# Public
has 'indent_block'        => ( is => 'ro', default => sub { 0 } );
has 'indent_perl_block'   => ( is => 'ro', default => sub { 2 } );
has 'mason_version'       => ( is => 'ro', required => 1, isa => \&validate_mason_version );
has 'perltidy_argv'       => ( is => 'ro', default => sub { '' } );
has 'perltidy_block_argv' => ( is => 'ro', default => sub { '' } );
has 'perltidy_line_argv'  => ( is => 'ro', default => sub { '' } );
has 'perltidy_tag_argv'   => ( is => 'ro', default => sub { '' } );

# Private
has '_is_code_block'    => ( is => 'lazy' );
has '_is_mixed_block'   => ( is => 'lazy' );
has '_marker_prefix'    => ( is => 'ro', default => sub { '__masontidy__' } );
has '_open_block_regex' => ( is => 'lazy' );
has '_subst_tag_regex'  => ( is => 'lazy' );

func validate_mason_version () {
    die "must be 1 or 2" unless $_[0] =~ /^[12]$/;
}

method _build__is_mixed_block () {
    return { map { ( $_, 1 ) } $self->mixed_block_names };
}

method _build__is_code_block () {
    return { map { ( $_, 1 ) } $self->code_block_names };
}

method _build__open_block_regex () {
    my $re = '<%(' . join( '|', $self->block_names ) . ')(\s+\w+)?>';
    return qr/$re/;
}

method _build__subst_tag_regex () {
    my $re = '<%(?!' . join( '|', $self->block_names, 'perl' ) . ')(.*?)%>';
    return qr/$re/;
}

method block_names () {
    return
      qw(after args around attr augment before class cleanup def doc filter flags init method once override shared text);
}

method code_block_names () {
    return qw(class init once shared);
}

method mixed_block_names () {
    return qw(after augment around before def method override);
}

method tidy ($source) {
    my $final = $self->tidy_method($source);
    $final .= "\n" if substr( $final, -1, 1 ) ne "\n";
    return $final;
}

method tidy_method ($source) {
    my @lines       = split( /\n/, $source );
    my @elements    = ();
    my $add_element = sub { push( @elements, [@_] ) };

    my $last_line        = scalar(@lines) - 1;
    my $open_block_regex = $self->_open_block_regex;
    my $mason1           = $self->mason_version == 1;
    my $mason2           = $self->mason_version == 2;

    for ( my $cur_line = 0 ; $cur_line <= $last_line ; $cur_line++ ) {
        my $line = $lines[$cur_line];

        # Begin Mason 2 filter invocation
        #
        if ( $mason2 && $line =~ /^%\s*(.*)\{\{\s*/ ) {
            $add_element->( 'perl_line', "given (__filter($1)) {" );
            next;
        }

        # End Mason 2 filter invocation
        #
        if ( $mason2 && $line =~ /^%\s*\}\}\s*/ ) {
            $add_element->( 'perl_line', "} # __end filter" );
            next;
        }

        # %-line
        #
        if ( $line =~ /^%/ ) {
            $add_element->( 'perl_line', substr( $line, 1 ) );
            next;
        }

        # <%perl> block, with both <%perl> and </%perl> on their own lines
        #
        if ( $line =~ /^\s*<%perl>\s*$/ ) {
            my ($end_line) =
              grep { $lines[$_] =~ /^\s*<\/%perl>\s*$/ } ( $cur_line + 1 .. $last_line );
            if ($end_line) {
                $add_element->( 'text', '<%perl>' );
                foreach my $line ( @lines[ $cur_line + 1 .. $end_line - 1 ] ) {
                    $add_element->( 'perl_line', "$line # __perl_block" );
                }
                $add_element->( 'text', '</%perl>' );
                $cur_line = $end_line;
                next;
            }
        }

        # Other blocks untouched
        #
        if ( my ($block_type) = ( $line =~ /$open_block_regex/ ) ) {
            my $end_line;
            foreach my $this_line ( $cur_line + 1 .. $last_line ) {
                if ( $lines[$this_line] =~ m{</%$block_type>} ) {
                    $end_line = $this_line;
                    last;
                }
            }
            if ($end_line) {
                my $block_contents = join( "\n", @lines[ $cur_line .. $end_line ] );
                $add_element->( 'block', $block_contents );
                $cur_line = $end_line;
                next;
            }
        }

        # Single line of text untouched
        #
        $add_element->( 'text', $line );
    }

    # Create content from elements with non-perl lines as comments; perltidy;
    # reassemble list of elements from tidied perl blocks and replaced elements
    #
    my $untidied_perl = join( "\n",
        map { $_->[0] eq 'perl_line' ? trim( $_->[1] ) : $self->replace_with_perl_comment($_) }
          @elements );
    $self->perltidy(
        source      => \$untidied_perl,
        destination => \my $tidied_perl,
        argv        => $self->perltidy_line_argv . " -fnl -fbl",
    );

    my @final_lines = ();
    foreach my $line ( split( /\n/, $tidied_perl ) ) {
        if ( my $marker = $self->marker_in_line($line) ) {
            push( @final_lines, $self->restore($marker)->[1] );
        }
        else {
            # Convert back filter invocation
            #
            if ($mason2) {
                $line =~ s/given\s*\(\s*__filter\s*\(\s*(.*?)\s*\)\s*\)\s*\{/$1 \{\{/;
                $line =~ s/\}\s*\#\s*__end filter/\}\}/;
            }

            if ( my ($real_line) = ( $line =~ /(.*?)\s*\#\s*__perl_block/ ) ) {
                if ( $real_line =~ /\S/ ) {
                    my $spacer = scalar( ' ' x $self->indent_perl_block );
                    push( @final_lines, $spacer . rtrim($real_line) );
                }
                else {
                    push( @final_lines, '' );
                }
            }
            else {
                push( @final_lines, "% " . $line );
            }
        }
    }
    my $final = join( "\n", @final_lines );

    # Tidy content in blocks other than <%perl>
    #
    my %replacements;
    undef pos($final);
    while ( $final =~ /$open_block_regex[\t ]*\n?/mg ) {
        my ( $block_type, $block_args ) = ( $1, $2 );
        my $start_pos = pos($final);
        if ( $final =~ /(\n?[\t ]*<\/%$block_type>)/g ) {
            my $length = pos($final) - $start_pos - length($1);
            my $block_contents = substr( $final, $start_pos, $length );
            $replacements{$block_contents} =
              $self->handle_block( $block_type, $block_args, $block_contents );
        }
        else {
            die sprintf( "no matching end tag for '<%%%s%s>' at char %d",
                $block_type, $block_args || '', $start_pos );
        }
    }
    while ( my ( $src, $dest ) = each(%replacements) ) {
        $final =~ s/\Q$src\E/$dest/;
    }

    # Tidy Perl in <% %> tags
    #
    my $subst_tag_regex = $self->_subst_tag_regex;
    $final =~ s/$subst_tag_regex/"<% " . $self->tidy_subst_expr($1) . " %>"/ge;

    # Tidy Perl in <% %> tags
    #
    $final =~ s/<&(.*?)&>/"<& " . $self->tidy_compcall_expr($1) . " &>"/ge;

    return $final;
}

method tidy_subst_expr ($expr) {
    $self->perltidy(
        source      => \$expr,
        destination => \my $tidied_expr,
        argv        => $self->perltidy_tag_argv,
    );
    return trim($tidied_expr);
}

method tidy_compcall_expr ($expr) {
    my $path;
    if ( ($path) = ( $expr =~ /^(\s*[\w\/\.][^,]+)/ ) ) {
        substr( $expr, 0, length($path) ) = "'$path'";
    }
    $self->perltidy(
        source      => \$expr,
        destination => \my $tidied_expr,
        argv        => $self->perltidy_tag_argv,
    );
    if ($path) {
        substr( $tidied_expr, 0, length($path) + 2 ) = $path;
    }
    return trim($tidied_expr);
}

method handle_block ($block_type, $block_args, $block_contents) {
    if ( $self->_is_code_block->{$block_type}
        || ( $block_type eq 'filter' && !defined($block_args) ) )
    {
        $block_contents = trim_lines($block_contents);
        $self->perltidy(
            source      => \$block_contents,
            destination => \my $tidied_block_contents,
            argv        => $self->perltidy_block_argv
        );
        $block_contents = trim($tidied_block_contents);
        my $spacer = scalar( ' ' x $self->indent_block );
        $block_contents =~ s/^/$spacer/mg;
    }
    elsif ( $self->_is_mixed_block->{$block_type}
        || ( $block_type eq 'filter' && defined($block_args) ) )
    {
        $block_contents = $self->tidy_method($block_contents);
    }
    return $block_contents;
}

method replace_with_perl_comment ($obj) {
    return "# " . $self->replace_with_marker($obj);
}

method replace_with_marker ($obj) {
    my $marker = join( "_", $self->_marker_prefix, $marker_count++ );
    $self->{markers}->{$marker} = $obj;
    return $marker;
}

method marker_in_line ($line) {
    my $marker_prefix = $self->_marker_prefix;
    if ( my ($marker) = ( $line =~ /(${marker_prefix}_\d+)/ ) ) {
        return $marker;
    }
    return undef;
}

method restore ($marker) {
    return $self->{markers}->{$marker};
}

method perltidy (%params) {
    $params{argv} .= ' ' . $self->perltidy_argv;
    my $errorfile;
    Perl::Tidy::perltidy(
        prefilter  => \&perltidy_prefilter,
        postfilter => \&perltidy_postfilter,
        errorfile  => \$errorfile,
        %params
    );
    die $errorfile if $errorfile;
}

func perltidy_prefilter ($buf) {
    $buf =~ s/\$\./\$__SELF__->/g;
    return $buf;
}

func perltidy_postfilter ($buf) {
    $buf =~ s/\$__SELF__->/\$\./g;
    $buf =~ s/ *\{ *\{/ \{\{/g;
    $buf =~ s/ *\} *\}/\}\}/g;
    return $buf;
}

func trim ($str) {
    for ($str) { s/^\s+//; s/\s+$// }
    return $str;
}

func rtrim ($str) {
    for ($str) { s/\s+$// }
    return $str;
}

func trim_lines ($str) {
    for ($str) { s/^\s+//m; s/\s+$//m }
    return $str;
}

1;

__END__

=pod

=head1 NAME

Mason::Tidy - Engine for masontidy

=head1 SYNOPSIS

    use Mason::Tidy;

    my $mc = Mason::Tidy->new(mason_version => 2);
    my $dest = $mc->tidy($source);

=head1 DESCRIPTION

This is the engine used by L<masontidy|masontidy> - read that first to get an
overview.

You can call this API from your own program instead of executing C<masontidy>.

=head1 CONSTRUCTOR PARAMETERS

=over

=item indent_block

=item indent_perl_block

=item mason_version (required)

=item perltidy_argv

=item perltidy_block_argv

=item perltidy_line_argv

=item perltidy_tag_argv

These options are the same as the equivalent C<masontidy> command-line options,
replacing dashes with underscore (e.g. the C<--indent-per-block> option becomes
C<indent_perl_block> here).

=back

=head1 METHODS

=over

=item tidy ($source)

Tidy component source I<$source> and return the tidied result. Throw fatal
error if source cannot be tidied (e.g. invalid syntax).

=item get_options ($argv, $params)

Use C<Getopt::Long::GetOptions> to parse the options in I<$argv> and place
params in I<$params> appropriate for passing into the constructor. Returns the
return value of C<GetOptions>.

=back

=cut
