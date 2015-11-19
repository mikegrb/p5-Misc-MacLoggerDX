tell application "MacLoggerDX"
	set qsoLogMode to system attribute "FLDIGI_MODEM"
	if qsoLogMode starts with "Olivia" then
		set qsoLogMode to "OLIVIA"
	else if qsoLogMode ends with "HELL" then
		set qsoLogMode to "HELL"
	else if qsoLogMode starts with "BPSK" then
		set qsoLogMode to characters 2 thru -1 of qsoLogMode as string
	end if
	
	lookup (system attribute "FLDIGI_LOG_CALL")
	delay 1
	setLogFrequency ((system attribute "FLDIGI_FREQUENCY") / 1000000)
	setLogMode qsoLogMode
	
end tell
