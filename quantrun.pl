#!/usr/bin/perl

# Use section
use Date::Calc qw(Today_and_Now);
use Date::Calc qw( Date_to_Days );
use Date::Calc qw(Add_Delta_Days);
use File::Copy;
use File::Basename;
use DBI;
use Net::SMTP;
use Net::SMTP::SSL;

# Date run and mypath
($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
my $starttime = "$year-$month-$day-$hour:$min:$sec";
my ($pname, $mypath, $type) = fileparse($0,qr{\..*});
$today = sprintf("%04d-%02d-%02d", $year, $month, $day);

# File and directories
$logfile = "$mypath/$pname.log";
$tradefile = "$mypath/$pname-trades.csv";
$balfile = "$mypath/$pname-bal.csv";

# SMTP
my $smtpserver = 'mail.7r.com.au';
my $smtpport = 465;
my $smtpuser   = 'shares@7r.com.au';
my $smtppassword = 'D3l3t312';
my $mailfrom = "shares\@7r.com.au";
my $mailto = "sstrijak\@7r.com.au";
my $subject = "$pname on $starttime";
my $otomessage = "";
my $message = "";

# mySQL
my $dbname = "shares";
my $dbhost = "localhost";
my $dbport = 3306;
my $dbuser = "shares";
my $dbpassword = "D3l3t312";
my $dbtable = "stocks";

# Flow control and reporting
my $keepgoing = 1;

# Script data
my $broker = 19.95;
my $date = "";
my $action = "";
my $code = "";
my $issues = 0;
my $price = 0;
my $oldissues = 0;
my $investment = 0;
my $perissue = 0;
my $amount = 0;
my $profit = 0;

my $firstyear = 2014;
my $firstmonth = 11;
my $firstday = 17;
my $firstdate = "2014-11-17";

my $tradeyear = $firstyear;
my $trademonth = $firstmonth;
my $tradeday = $firstday;

my $bank = 0;
my %entrydates;
my %exitdates;
my %codeexits;
my %portissues;
my %portinvest;

open LOG, ">>", $logfile;
open TRADES, ">", $tradefile;
open BAL, ">", $balfile;

print TRADES "Date,Order,Code,Issues,Price,Invest/Profit,Bank\n";
print BAL "Date,Code,Issues,Close,Exit,Value,Profit,Bank\n";

my $dsn = "DBI:mysql:database=$dbname;host=$dbhost;port=$dbport";
my $dbh = DBI->connect($dsn, $dbuser, $dbpassword);
my $error = $dbh->{'mysql_error'};

if ( $error)
{
	$thismessage = "Error connecting to database: $error";
	logentry ( $thismessage );
	$message .= "$thismessage\n";
	$keepgoing = 0;
}

$qrstop = 0;

if ($keepgoing)
{
	$sql = "select date, code, `exit` from quantsig where `order`='buy' order by date asc";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	$entrycount = 0;
	while (@row = $sth->fetchrow_array())
	{
		$date = $row[0];
		$code = $row[1];
		$exit = $row[2];
		$entrydates{$date}{$code} = $exit;
		$codeexits {$code}{$date}= $exit;
	}
	$sth->finish();
	
	$sql = "select date, code from quantexit where position='long' order by date asc";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
	$exitcount = 0;
	while (@row = $sth->fetchrow_array())
	{
		$date = $row[0];
		$code = $row[1];
		$exitdates {$date}{$code} = $code;
	}
	$sth->finish();
}
	
$qrstop++;

while ($keepgoing)
{
	$tradedate = sprintf("%04d-%02d-%02d", $tradeyear, $trademonth, $tradeday);
	print "$tradedate\n";

	%{$prices} = () ;
	$sql = "select code, open, high, low, close from daily where date='$tradedate'";
	$sth = $dbh->prepare($sql);
	$result = $sth->execute();
$qrstop++;
	while (@row = $sth->fetchrow_array())
	{
		$code = $row[0];
		$prices{$code}{'open'} = $row[1];
		$prices{$code}{'high'} = $row[2];
		$prices{$code}{'low'} = $row[3];
		$prices{$code}{'close'} = $row[4];
	}
	$sth->finish();
	
$qrstop++;

	# Buy on entry signal
	foreach $code ( keys %{$entrydates{$tradedate}} )
	{
		if ( defined ( $prices{$code}{'high'} ) )
		{
			$high = $prices{$code}{'high'};
			$issues = int 980.05 / $high;
			$invest = $issues * $high + 19.95;
			$bank -= $invest;
			$portissues{$code} += $issues;
			$portinvest{$code} += $invest;
			print TRADES "$tradedate,buy,$code,$issues,$high,$invest,$bank\n";
		}
		else
		{
			print "Price for $code on $tradedate (entry) is not defined\n";
		}
	}
	
$qrstop++;

	# Sell on exit signal
#	foreach $code ( keys %{$exitdates{$tradedate}} )
#	{
#		if ( defined ( $portissues {$code} ) )
#		{
#			if ( defined ($prices{$code}{'low'}) )
#			{
#				$low = $prices{$code}{'low'};
#				$issues = $portissues {$code};
#				$value = $issues * $low - 19.95;
#				$invest = $portinvest{$code};
#				$bank += $value;
#				$profit = $value - $invest;
#				delete $portissues {$code};
#				delete $portinvest {$code};
#				print TRADES "$tradedate,sell-signal,$code,$issues,$low,$profit,$bank\n";
#			}
#			else
#			{
#				print "Price for $code on $tradedate (exit) is not defined\n";
#			}
#		}
#	}
	
#$qrstop++;

	# Sell on low < exit
	foreach $code ( keys %portissues )
	{
		if ( defined ( $prices{$code}{'low'}) )
		{
			$low = $prices{$code}{'low'};
			$newexit = $low * 0.8;
			if ( defined ( $codeexits {$code} ) )
			{
				$exitdate = $firstdate;
				$exit = 0;
				foreach $date ( keys %{$codeexits {$code}} )
				{
					if ( $date le $tradedate )
					{
						if ( $date ge $exitdate)
						{
							$exitdate = $date;
							$exit = $codeexits {$code}{$date};
						}
					}
				}
				
				if ( $newexit > $exit )
				{
					$codeexits {$code}{$exitdate} = $newexit;
					$exit = $newexit;
				}
				
				if ( defined ( $prices{$code}{'low'}) )
				{
					if ( $low < $exit )
					{
						$issues = $portissues {$code};
						$value = $issues * $low - 19.95;
						$invest = $portinvest{$code};
						$bank += $value;
						$profit = $value - $invest;
						delete $portissues {$code};
						delete $portinvest {$code};
						print TRADES "$tradedate,sell-price,$code,$issues,$low,$profit,$bank\n";
					}
				}
			}
			else
			{
				print "Exit price for $code on $tradedate is not defined\n";
			}
		}
		else
		{
			print "Price for $code on $tradedate (exit) is not defined\n";
		}
	}
	
$qrstop++;

	# Print current balance
	$portbalance = 0;
	foreach $code ( keys %portissues )
	{
		if ( defined ( $prices{$code}{'close'}) )
		{
			$issues = $portissues { $code };
			$close = $prices{$code}{'close'};
			$value = $issues * $close;
			$invest = $portinvest { $code };
			$profit = $value - $invest ;
			
			#exit
			$exitdate = $firstdate;
			$exit = 0;
			foreach $date ( keys %{$codeexits {$code}} )
			{
				if ( $date le $tradedate )
				{
					if ( $date ge $exitdate)
					{
						$exitdate = $date;
						$exit = $codeexits {$code}{$date};
					}
				}
			}

			#print BAL "Date,Code,Issues,Close,Exit,Value,Profit,Bank\n";
			print BAL "$tradedate,$code,$issues,$close,$exit,$value,$profit\n";
			$portbalance += $close * $portissues { $code };
		}
		else
		{
			print "Exit price for $code on $tradedate is not defined\n";
		}
	}
	
$qrstop++;

	$profit = $portbalance + $bank;
	#print BAL "Date,Code,Issues,Close,Exit,Value,Profit,Bank\n";
	print BAL "$tradedate,balance,,,,$portbalance,$profit,$bank\n";
	($tradeyear,$trademonth,$tradeday) = Add_Delta_Days($tradeyear,$trademonth,$tradeday, 1);
	if ( $tradedate ge $today ) { $keepgoing = 0; }
	if ( $tradeday == 1 ) { $qrdstop = 1; }
#	if ( $qrstop > 1000 ) { $keepgoing = 0; }
}

# closing
# sendreport ( "Completed" );
close LOG;
close TRADES;
close BAL;

sub sendreport () {
	my $message = $_[0];
	my $smtp = Net::SMTP::SSL->new($smtpserver, Port=>$smtpport, Timeout => 10, Debug => 1);
	$smtp->auth($smtpuser,$smtppassword);
	$smtp->mail($mailfrom);
	$smtp->to($mailto);
	$smtp->recipient($mailto);
	$smtp->data();
	$smtp->datasend("To: $mailto\n");
	$smtp->datasend("From: $mailfrom\n");
	$smtp->datasend("Subject: $subject\n");
	$smtp->datasend("\n"); # done with header
	$smtp->datasend($message);
	$smtp->dataend();
	
	$smtpcode = $smtp->code();
	$smtpmsg = $smtp->message();
	
	$smtp->quit(); # all done. message sent.
	logentry ( "Mail send result: $smtpcode: $smtpmsg" );
}

sub logentry () {
	my $entry = $_[0];
	print STDOUT "$entry\n";
	($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
	$now = "$year-$month-$day-$hour:$min:$sec";
	print LOG $now; 
	print LOG ": $entry\n"; 
}

