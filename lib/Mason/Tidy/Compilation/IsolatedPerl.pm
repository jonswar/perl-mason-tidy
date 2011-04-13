package Mason::Tidy::Compilation::IsolatedPerl;
use Mason::Tidy::Moose;
use Perl::Tidy qw();
extends 'Mason::Tidy::Compilation';

method handle_default () { }

method handle_block ($pos, $length, $block_type) {
    if ( $block_type =~ /^(?:init|class|once)$/ ) {

        # Get what's inside the <%...> and </%...> tags
        #
        my $untidied = substr(
            $self->{source},
            $pos + length($block_type) + 3,
            $length - ( length($block_type) * 2 + 7 )
        );
        my $tidied = $self->perltidy($untidied);
        for ($tidied) { s/^\s+//; s/\s+$// }
        $tidied = "<%$block_type>\n$tidied\n</%$block_type>";
        push( @{ $self->{to_replace} }, [ $pos, $length, $tidied ] );
    }
}

method handle_substitution ($pos, $length) {
    my $untidied = substr( $self->{source}, $pos + 2, $length - 4 );
    my $tidied = $self->perltidy($untidied);
    chomp($tidied);
    $tidied = "<% $tidied %>";
    push( @{ $self->{to_replace} }, [ $pos, $length, $tidied ] );
}

method replace_all () {
    my $adjust = 0;
    foreach my $repl ( @{ $self->{to_replace} } ) {
        my ( $pos, $length, $tidied ) = @$repl;
        substr( $self->{source}, $pos + $adjust, $length ) = $tidied;
        $adjust += ( length($tidied) - $length );
    }
}

method transform () {
    $self->parse;
    $self->replace_all;
}

method perltidy ($untidied) {
    my $tidied;
    Perl::Tidy::perltidy( source => \$untidied, destination => \$tidied, argv => '-noll' );
    return $tidied;
}

1;
