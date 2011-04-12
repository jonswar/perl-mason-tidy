package Mason::Tidy::Compilation::Substitution;
use Mason::Tidy::Moose;
use Perl::Tidy;
extends 'Mason::Tidy::Compilation';

method handle_default () { }

method handle_substitution ($pos, $length) {
    my $untidied = substr( $self->{source}, $pos + 2, $length - 4 );
    my $tidied;
    Perl::Tidy::perltidy( source => \$untidied, destination => \$tidied, argv => '-noll' );
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

1;
