package HTML;

use URI;
use URI::QueryParam;

sub New {
    my $ClassName = shift;
    my $Self      = shift;
    bless $Self, $ClassName;
    return $Self;
}

sub Hash2Query {
    my ($Self, $Hash) = @_;
    my $URI = URI->new;
    $URI->query_form_hash($Hash);
    return $URI->query;
}

sub HyperLink {
    my ($Self, $Attr) = @_;
    return qq!<a href="$Attr->{HREF}">$Attr->{Text}</a>!;
}

sub NodeLink {
    my ($Self, $Attr) = @_;
    my $HREF = $Self->Hash2Query({
        FilterSchema          => $Attr->{Node}->{schema},
        FilterTable           => $Attr->{Node}->{table},
        FilterColumn          => $Attr->{Node}->{column},
        FilterValue           => $Attr->{Node}->{value},
        ShowUniqueNamesForIDs => $Attr->{ShowUniqueNamesForIDs}
    });
    if ($Attr->{Type} eq 'TABLE') {
        return $Self->HyperLink({
            HREF  => $HREF,
            Text => ($Attr->{Node}->{schema} eq 'public' ? '' : $Attr->{Node}->{schema} . '.') . $Attr->{Node}->{table}
        });
    } elsif ($Attr->{Type} eq 'VALUE' && $Attr->{ShowUniqueNamesForIDs} eq '1' && defined($Attr->{Node}->{label})) {
        return $Self->HyperLink({
            HREF  => $HREF,
            Text => $Attr->{Node}->{label}
        });
    }
    return $Self->HyperLink({
        HREF  => $HREF,
        Text => $Attr->{Node}->{value}
    });
}

sub Select {
    my ($Self, $Attr) = @_;
    my $HTML = qq!
        <select name="$Attr->{Name}" ! . ($Attr->{OnChangeSubmit} ? qq! onchange="this.form.submit()"! : '') . qq!>
            <option value="$Attr->{DefaultValue}">$Attr->{DefaultText}</option>
    !;
    foreach my $Value (@{$Attr->{Options}}) {
        if ($Attr->{SelectedValue} eq $Value) {
            $HTML .= qq!<option selected="selected">$Value</option>!;
        } else {
            $HTML .= qq!<option>$Value</option>!;
        }
    }
    $HTML .= qq!</select>!;
    return $HTML;
}

sub Input {
    my ($Self, $Attr) = @_;
    my $HTML = '';

    my $Dec;
    my $Inc;
    if (defined($Params->{Increment}) && $Attr->{Value} = ~ m/^\d+$/) {
        $Dec = ($Attr->{Value} - $Params->{Increment});
        if ($Dec < $Attr->{Min}) {
            $Dec = undef;
        }
        $Inc = ($Attr->{Value} + $Params->{Increment});
        if ($Inc > $Attr->{Max}) {
            $Inc = undef;
        }
    }
    if (defined($Dec)) {
        $HTML .= qq!<input type="button" onClick="document.getElementById('$Attr->{Name}').value = '$Dec'; document.getElementById('$Self->{FormID}').submit();" value="$Dec"/>!;
    }
    $HTML .= qq!<input id="$Attr->{Name}" name="$Attr->{Name}" value="$Attr->{Value}"/>!;
    if (defined($Inc)) {
        $HTML .= qq!<input type="button" onClick="document.getElementById('$Attr->{Name}').value = '$Inc'; document.getElementById('$Self->{FormID}').submit();" value="$Inc"/>!;
    }
    return $HTML;
}

sub Cell {
    my ($Self, $Attr) = @_;
    my @Classes = ('cell');
    my $Text    = $Attr->{Value};
    my $HTML = '';
    if (!defined($Text)) {
        push @Classes, 'null';
        $Text = 'NULL';
    } elsif (length($Text) > 80) {
        $Text =~ s!^(.{40}).*?(.{40})$!$1...$2!;
        push @Classes, 'truncated';
    }
    $HTML .= qq!<div class="! . join(' ',@Classes) . qq!">$Text</div>!;
    return $HTML;
}

sub Submit {
    my ($Self, $Attr) = @_;
    return qq!<input type="submit" value="$Attr->{Value}"/>!;
}

sub Body {
    my ($Self, $InnerHTML) = @_;
    return qq!<body translate="no">$InnerHTML</form>!;
}

sub Head {
    my ($Self, $Attr) = @_;
    return qq!
        <head>
            <meta charset="UTF-8" />
            <meta http-equiv="Content-language" content="en">
            <style type="text/css">$Attr->{CSS}</style>
        </head>
    !;
}

sub HTML {
    my ($Self, $InnerHTML) = @_;
    return qq!<html>$InnerHTML</html>!;
}

sub Form {
    my ($Self, $Attr, $InnerHTML) = @_;
    $Self->{FormID} = $Attr->{ID};    
    return qq!<form id="$Attr->{ID}">$InnerHTML</form>!;
}

sub ResetButton {
    my ($Self, $Attr) = @_;
    my $HTML = '';
    $HTML .= qq!<input type="button" onClick="document.getElementById('$Attr->{Name}').value = ''; document.getElementById('$Self->{FormID}').submit();" value="$Attr->{Text}"/>!;
}

sub ToggleButton {
    my ($Self, $Attr) = @_;
    my $HTML = '';
    my $CurValue   = $Self->{Params}->{$Attr->{Name}} || '0';
    my $InvValue   = $CurValue eq '0' ? '1' : '0';
    my $ButtonText = $CurValue eq '0' ? $Attr->{OnButton} : $Attr->{OffButton};
    $HTML .= qq!<input type="hidden" name="$Attr->{Name}" id="$Attr->{Name}" value="$CurValue" />!;
    $HTML .= qq!<input type="button" onClick="document.getElementById('$Attr->{Name}').value = '$InvValue'; document.getElementById('$Self->{FormID}').submit();" value="$ButtonText"/>!;
    return $HTML;
}

1;