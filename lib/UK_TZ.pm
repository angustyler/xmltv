# Timezone stuff.
#
# This is hardcoded for British timezones, but it shouldn't be too
# hard to adapt for other countries in Europe.
#
# Actually, now there is some other general time stuff in here too.
#
# $Id: UK_TZ.pm,v 1.1 2002/10/27 09:28:10 epaepa Exp $
#

package XMLTV::UK_TZ;
use Date::Manip; # no Date_Init(), that can be done by the app
use XMLTV::TZ qw(gettz);

# Memoize some subroutines if possible.  FIXME commonize to
# XMLTV::Memoize.  We are memoizing our own routines plus gettz() from
# XMLTV::TZ, that too needs sorting out.
#
eval { require Memoize };
unless ($@) {
    foreach (qw(parse_uk_date date_to_uk bst_dates
		ParseDate UnixDate DateCalc Date_Cmp
		ParseDateDelta gettz)) {
	Memoize::memoize($_) or die "cannot memoize $_: $!";
    }
}

use base 'Exporter'; use vars '@EXPORT';
@EXPORT = qw(parse_uk_date date_to_uk);

# parse_uk_date()
#
# Wrapper for ParseDate() that tries to guess what timezone a date is
# in (UTC or BST).  If the date already has either of these it is left
# alone.
#
# This will probably fail horribly if you use it for dates which
# aren't in either of these timezones.  But since summer time starts
# and ends at the same time throughout the EU it wouldn't be hard to
# make it work for some other countries.
#
# Parameters:
#   unparsed date from the UK (or other places using UTC/BST)
#
#   (optional) timezone to assume if ambiguous (defaults to BST if not
#   given or 'false')
#
# Returns: parsed date, or undef if error
#
# There's a one hour window where dates are ambigous; we assume UTC for
# these.  Similarly there's a one hour window
# where dates without a timezone are impossible; we return undef on
# those.
#
sub parse_uk_date($;$) {
    die 'usage: parse_uk_date(unparsed date [, default tz])'
      unless (1 <= @_ and @_ < 3);
    my $date = shift;
    my $default_tz = $_[0] || 'BST';

    if (defined gettz($date)) {
	# An explicit timezone, no need for any funny business
	return ParseDate($date);
    }

    my $dp = ParseDate($date);
    die "bad date $date" if not defined $dp or $dp eq '';

    # Start and end of summer time in that year, in UTC
    my ($start_bst, $end_bst) = @{bst_dates(UnixDate($dp, '%Y'))};

    # The clocks shift backwards and forwards by one hour.
    my $clock_shift = "1 hour";

    # The times that the clocks go forward to in spring (local time)
    my $start_bst_skipto = DateCalc($start_bst, "+ $clock_shift");

    # The local time when the clocks go back
    my $end_bst_backfrom = DateCalc($end_bst, "+ $clock_shift");

    if (Date_Cmp($dp, $start_bst) < 0) {
	# Before the start of summer time.
	return $dp;
    }
    elsif (Date_Cmp($dp, $start_bst) == 0) {
	# Exactly _at_ the start of summer time.  Really such a date
	# should not exist since the clocks skip forward an hour at
	# that point.
	#
	return $dp;
    }
    elsif (Date_Cmp($dp, $start_bst_skipto) < 0) {
	# Date is impossible (time goes from from $start_bst UTC to
	# $start_bst_skipto BST).
	#
	return undef;
    }
    elsif (Date_Cmp($dp, $end_bst) < 0) {
	# During summer time.
	return Date_ConvTZ($dp, 'BST', 'UTC');
    }
    elsif (Date_Cmp($dp, $end_bst_backfrom) <= 0) {
#	warn("$date is ambiguous "
#	     . "(clocks go back from $end_bst_backfrom BST to $end_bst UTC), "
#	     . "assuming $default_tz" );

	return Date_ConvTZ($dp, $default_tz, 'UTC');
    }
    else {
	# Definitely after the end of summer time.
	return $dp;
    }
}


# date_to_uk()
#
# Take a date in UTC and convert it to a BST date if needed.
#
# Parameters: date in UTC (from ParseDate())
#
# Returns ref to list of
#   new date (maybe shifted by one hour),
#   timezone of new date ('UTC' or 'BST')
#
# For example, date_to_uk of 13:00 on June 10th 2000 would be 14:00
# BST on the same day.  The input and output date are both in
# Date::Manip internal format.
#
sub date_to_uk($) {
    die 'usage: date_to_uk(date in Date::Manip format)' if @_ != 1;
    my $d = shift; die if (not defined $d) or ($d !~ /\S/);

    my $year = UnixDate($d, '%Y');
    if ((not defined $year) or ($year !~ tr/0-9//)) {
	die "cannot get year from '$d'";
    }

    # Find the start and end dates in March and October
    my ($start_bst, $end_bst) = @{bst_dates($year)};

    # The clocks shift backwards and forwards by one hour.
    my $clock_shift = "1 hour";

    if (Date_Cmp($d, $start_bst) < 0) {
	# Before the start of summer time.
	return [ $d, 'UTC' ];
    }
    elsif (Date_Cmp($d, $end_bst) < 0) {
	# During summer time.
	return [ DateCalc($d, "+ $clock_shift"), 'BST' ];
    }
    else {
	# After summer time.
	return [ $d, 'UTC' ];
    }
}


# bst_dates()
#
# Return the dates (in UTC) when British Summer Time starts and ends in
# a given year.
#
# According to <http://www.rog.nmm.ac.uk/leaflets/summer/summer.html>,
# summer time starts at 01:00 on the last Sunday in March, and ends at
# 01:00 on the last Sunday in October.  (That's 01:00 UTC in both
# cases, BTW.)  This has been the case since 1998 - earlier dates are
# not handled.
#
# Parameters: year (only 1998 or later works)
#
# Returns: ref to list of
#   start time and date of summer time (in UTC)
#   end time and date of summer time (in UTC)
#
sub bst_dates($) {
    die 'usage: bst_dates(year)' if @_ != 1;
    my $year = shift;
    die "don't know about BST before 1998" if $year < 1998;

    my ($start_bst, $end_bst);
    foreach (1 .. 31) {
	my $mar = "$year-03-$_" . ' 01:00';
	my $mar_d = ParseDate($mar) or die "cannot parse $mar";
	$start_bst = $mar_d if UnixDate($mar_d, "%A") =~ /Sunday/;

	# A time between '00:00' and '01:00' just before the last
	# Sunday in October is ambiguous.
	#
	my $oct = "$year-10-$_" . ' 01:00';
	my $oct_d = ParseDate($oct) or die "cannot parse $oct";
	$end_bst = $oct_d if UnixDate($oct_d, "%A") =~ /Sunday/;
    }
    die if not defined $start_bst or not defined $end_bst;

    return [ $start_bst, $end_bst ];
}


1;
