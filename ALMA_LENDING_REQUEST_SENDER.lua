-- ALMA LENDING REQUEST SENDER, version 1.24 (December 25, 2023)
-- This Server Addon was developed by Bill Jones (SUNY Geneseo), Tim Jackson (SUNY Libraries Shared Services), and Angela Persico (University at Albany)
-- The purpose of this Addon is to send Borrowing requests from ILLiad to Alma, and Hold requests for owned items
-- The Addon monitors RequestType: Loan in a configurable ILLiad queue for ProcessType: Borrowing
-- For usernames, the Addon allows staff to select which field in the Users table to use. Potential options include Username, SSN, and email
-- The Addon uses an Alma SRU Lookup to determine availability and to gather item information
-- The Addon uses the Bibs API in order to lookup item process_type for unavailable items to determine if MISSING, IN BINDERY, in ILL, or another process_type
-- The Addon uses the Users API 'Retrieve user loans' call to analyze active requests to sift out duplicate ILL requests
-- The Addon sends a Hold request to Alma using the Users API 'Create user request' call
-- The Addon sends an Borrowing request to Alma using the Users API 'Create user request for resource sharing' call
-- The Addon uses a file called error_routing.txt to route specific API numerical errors to specific ILLiad queues
-- The Addon uses a file called sublibraries.txt to crosswalk between the ILLiad user NVTGC code (Example: ILL) and Alma Pickup Location code (Example: GENMN)
-- The Addon uses a file called process_type_router.txt to route specific process_type values (like MISSING, or IN BINDERY, or RESERVES) to specific queues
-- The Addon uses a file called excluded_locations.txt to make specific shelving locations unavailable for Hold requests 

local Settings = {};
Settings.Alma_Base_URL = GetSetting("Alma_Base_URL");
Settings.Alma_Users_API_Key = GetSetting("Alma_Users_API_Key");
Settings.Alma_Bibs_API_Key = GetSetting("Alma_Bibs_API_Key");
Settings.ItemSearchQueue = GetSetting("ItemSearchQueue");
Settings.ItemSuccessHoldRequestQueue = GetSetting("ItemSuccessHoldRequestQueue");
Settings.ItemFailHoldRequestQueue = GetSetting("ItemFailHoldRequestQueue");
Settings.Alma_Institution_Code = GetSetting("Alma_Institution_Code");
Settings.Full_Alma_URL = GetSetting("Full_Alma_URL");
Settings.NoISBNandNoOCLCNumberReviewQueue = GetSetting("NoISBNandNoOCLCNumberReviewQueue");
Settings.ItemInExcludedLocationNeedsReviewQueue = GetSetting("ItemInExcludedLocationNeedsReviewQueue");
Settings.AddonWorkerName = GetSetting("AddonWorkerName");
Settings.UltimateDebug = GetSetting("UltimateDebug");

local isCurrentlyProcessing = false;
local client = nil;

-- Assembly Loading and Type Importation
luanet.load_assembly("System");
local Types = {};
Types["WebClient"] = luanet.import_type("System.Net.WebClient");
Types["System.IO.StreamReader"] = luanet.import_type("System.IO.StreamReader");
Types["System.Type"] = luanet.import_type("System.Type");


function Init()
	LogDebug("Initializing ALMA LENDING REQUEST SENDER Server Addon");
	RegisterSystemEventHandler("SystemTimerElapsed", "TimerElapsed");
end

function TimerElapsed(eventArgs)
	LogDebug("Processing ALMA LENDING REQUEST SENDER Items");
	if not isCurrentlyProcessing then
		isCurrentlyProcessing = true;

		-- Process Items
		local success, err = pcall(ProcessItems);
		if not success then
			LogDebug("There was a fatal error processing the items.")
			LogDebug("Error: " .. err);
		end
		isCurrentlyProcessing = false;
	else
		LogDebug("Still processing ALMA LENDING REQUEST SENDER Items");
	end
end

function ProcessItems()
	if Settings.ItemSearchQueue == "" then
		LogDebug("The configuration value for ItemSearchQueue has not been set in the config.xml file.  Stopping Addon.");
	end
	if Settings.ItemSearchQueue ~= "" then
		ProcessDataContexts("TransactionStatus", Settings.ItemSearchQueue, "HandleContextProcessing");
	end
end

function cleanup_field(title)
-- " = &quot;
-- ' = &apos;
-- < = &lt;
-- > = &gt;
-- & = &amp;
local cleaned_string = title;
cleaned_string = cleaned_string:gsub('&', '&amp;'):gsub('"', '&quot;'):gsub("'", '&apos;'):gsub('<', '&lt;'):gsub('>', '&gt;'); 
return cleaned_string;
end



function extract_isbn(isbn)		
local currentTN_int = GetFieldValue("Transaction", "TransactionNumber");
local transactionNumber = luanet.import_type("System.Convert").ToDouble(currentTN_int);
local isbn = isbn;
	isbn = isbn:gsub('-', '');
	LogDebug("Attempting to extract ISBN from: " .. isbn);
	
	if string.find(isbn, '%d%d%d%d%d%d%d%d%d%d%d%d%d') then
		local i = string.match(isbn, '%d%d%d%d%d%d%d%d%d%d%d%d%d');
		LogDebug("Extracted ISBN: " .. i .. " from original ISBN: " .. isbn);
		new_ISBN = i;
		if validate_isbn(new_ISBN) then
			ExecuteCommand("AddNote",{transactionNumber, "Extracted ISBN: " .. i .. " from original ISBN: " .. isbn});
			SetFieldValue("Transaction", "ISSN", new_ISBN);
			SaveDataSource("Transaction");
			return new_ISBN;		
		else
			LogDebug("The Extracted ISBN: " .. i .. " from original ISBN: " .. isbn .. " is not a valid ISBN. Please try to manually fix the ISBN for the transaction and reprocess.");
			ExecuteCommand("AddNote",{transactionNumber, "The Extracted ISBN: " .. i .. " from original ISBN: " .. isbn .. " is not a valid ISBN. Please try to manually fix the ISBN for the transaction and reprocess."});
			return false
		end	
	end
	
	if string.find(isbn, '%d%d%d%d%d%d%d%d%d%d%d%d' .. "X") then
		local j = string.match(isbn, '%d%d%d%d%d%d%d%d%d%d%d%d' .. "X");
		LogDebug("Extracted ISBN: " .. j .. " from original ISBN: " .. isbn);
		new_ISBN = j;
		if validate_isbn(new_ISBN) then
			ExecuteCommand("AddNote",{transactionNumber, "Extracted ISBN: " .. j .. " from original ISBN: " .. isbn});
			SetFieldValue("Transaction", "ISSN", new_ISBN);
			SaveDataSource("Transaction");
			return new_ISBN;		
		else
			LogDebug("The Extracted ISBN: " .. j .. " from original ISBN: " .. isbn .. " is not a valid ISBN. Please try to manually fix the ISBN for the transaction and reprocess.");
			ExecuteCommand("AddNote",{transactionNumber, "The Extracted ISBN: " .. j .. " from original ISBN: " .. isbn .. " is not a valid ISBN. Please try to manually fix the ISBN for the transaction and reprocess."});
			return false
		end
	end
	
	if string.find(isbn, '%d%d%d%d%d%d%d%d%d%d%d%d' .. "x") then
		local j = string.match(isbn, '%d%d%d%d%d%d%d%d%d%d%d%d' .. "x");
		LogDebug("Extracted ISBN: " .. j .. " from original ISBN: " .. isbn);
		new_ISBN = j;
		if validate_isbn(new_ISBN) then
			ExecuteCommand("AddNote",{transactionNumber, "Extracted ISBN: " .. j .. " from original ISBN: " .. isbn});
			SetFieldValue("Transaction", "ISSN", new_ISBN);
			SaveDataSource("Transaction");
			return new_ISBN;		
		else
			LogDebug("The Extracted ISBN: " .. j .. " from original ISBN: " .. isbn .. " is not a valid ISBN. Please try to manually fix the ISBN for the transaction and reprocess.");
			ExecuteCommand("AddNote",{transactionNumber, "The Extracted ISBN: " .. j .. " from original ISBN: " .. isbn .. " is not a valid ISBN. Please try to manually fix the ISBN for the transaction and reprocess."});
			return false
		end
	end
			
	if string.find(isbn, '%d%d%d%d%d%d%d%d%d%d') then
		local i = string.match(isbn, '%d%d%d%d%d%d%d%d%d%d');
		LogDebug("Extracted ISBN: " .. i .. " from original ISBN: " .. isbn);	
		new_ISBN = i;
		if validate_isbn(new_ISBN) then
			ExecuteCommand("AddNote",{transactionNumber, "Extracted ISBN: " .. i .. " from original ISBN: " .. isbn});
			SetFieldValue("Transaction", "ISSN", new_ISBN);
			SaveDataSource("Transaction");
			return new_ISBN;		
		else
			LogDebug("The Extracted ISBN: " .. i .. " from original ISBN: " .. isbn .. " is not a valid ISBN. Please try to manually fix the ISBN for the transaction and reprocess.");
			ExecuteCommand("AddNote",{transactionNumber, "The Extracted ISBN: " .. i .. " from original ISBN: " .. isbn .. " is not a valid ISBN. Please try to manually fix the ISBN for the transaction and reprocess."});
			return false
		end
	end
	
	if string.find(isbn, '%d%d%d%d%d%d%d%d%d' .. "X") then
		local j = string.match(isbn, '%d%d%d%d%d%d%d%d%d' .. "X");
		LogDebug("Extracted ISBN: " .. j .. " from original ISBN: " .. isbn);
		new_ISBN = j;
		if validate_isbn(new_ISBN) then
			ExecuteCommand("AddNote",{transactionNumber, "Extracted ISBN: " .. j .. " from original ISBN: " .. isbn});
			SetFieldValue("Transaction", "ISSN", new_ISBN);
			SaveDataSource("Transaction");
			return new_ISBN;		
		else
			LogDebug("The Extracted ISBN: " .. j .. " from original ISBN: " .. isbn .. " is not a valid ISBN. Please try to manually fix the ISBN for the transaction and reprocess.");
			ExecuteCommand("AddNote",{transactionNumber, "The Extracted ISBN: " .. j .. " from original ISBN: " .. isbn .. " is not a valid ISBN. Please try to manually fix the ISBN for the transaction and reprocess."});
			return false
		end
	end
	
	if string.find(isbn, '%d%d%d%d%d%d%d%d%d' .. "x") then
		local j = string.match(isbn, '%d%d%d%d%d%d%d%d%d' .. "x");
		LogDebug("Extracted ISBN: " .. j .. " from original ISBN: " .. isbn);
		new_ISBN = j;
		if validate_isbn(new_ISBN) then
			ExecuteCommand("AddNote",{transactionNumber, "Extracted ISBN: " .. j .. " from original ISBN: " .. isbn});
			SetFieldValue("Transaction", "ISSN", new_ISBN);
			SaveDataSource("Transaction");
			return new_ISBN;		
		else
			LogDebug("The Extracted ISBN: " .. j .. " from original ISBN: " .. isbn .. " is not a valid ISBN. Please try to manually fix the ISBN for the transaction and reprocess.");
			ExecuteCommand("AddNote",{transactionNumber, "The Extracted ISBN: " .. j .. " from original ISBN: " .. isbn .. " is not a valid ISBN. Please try to manually fix the ISBN for the transaction and reprocess."});
			return false
		end
	end
end


function validate_isbn(isbn)
LogDebug("Initializing ISBN Validator.");

local isbn = isbn;

if isbn == "" or isbn == nil then
LogDebug("ISBN Validator > There is no ISBN available.  Skipping ISBN Validator.");
return true
end

local currentTN_int = GetFieldValue("Transaction", "TransactionNumber");
local transactionNumber = luanet.import_type("System.Convert").ToDouble(currentTN_int);

local is_13long = false;
local is_10long = false;
 
isbn = isbn:gsub('-', '');
    
	-- check if 10 digits long
	if isbn:match('^%d%d%d%d%d%d%d%d%d[%dX]$') then
	LogDebug("ISBN Validator > The ISBN is 10 Digits long.");
      is_10long = true;
    end
	
	-- check if 13 digits long
	if isbn:match('^%d%d%d%d%d%d%d%d%d%d%d%d[%dX]$') then
	LogDebug("ISBN Validator > The ISBN is 13 Digits long.");
      is_13long = true;
    end
	
	if not is_10long and not is_13long then
	LogDebug("ISBN Validator > The ISBN is not 10 Digits or 13 Digits long.");
	ExecuteCommand("AddNote",{transactionNumber, "ISBN Validator > The ISBN is not 10 Digits or 13 Digits long."});
	return false
	end
	
	-- if 10 digits long, validate the number  
	-- Multiply each of the first 9 digits by a number in the descending sequence from 10 to 2, and sum the results. Divide the sum by 11. The remainder should be 0.
	if is_10long and not is_13long then
		local sum = 0;
		local sum_string = "";
		for i = 1, 10 do
			sum = sum + (11 - i) * (tonumber(isbn:sub(i, i)) or 10);
			sum_string = sum_string .. tostring((11 - i) * (tonumber(isbn:sub(i, i)) or 10)) .. "+";
		end
		
		local remainder = sum % 11;
		
		if remainder == 0 then
		LogDebug("ISBN Validator > The 10ISBN sum is: " .. sum_string:sub(1, -2) .. "=" .. sum .. ". The remainder when " .. sum .. "/11 = " .. remainder);		
		LogDebug("ISBN Validator > The 10 digit ISBN: " .. isbn .. " is Valid.");
		return true
		end
		if remainder ~= 0 then
		LogDebug("ISBN Validator > The 10ISBN sum is: " .. sum_string:sub(1, -2) .. "=" .. sum .. ". The remainder when " .. sum .. "/11 = " .. remainder);		
		LogDebug("ISBN Validator > The 10 digit ISBN: " .. isbn .. " is Not Valid.");
		ExecuteCommand("AddNote",{transactionNumber, "ISBN Validator > The 10 digit ISBN: " .. isbn .. " is Not Valid."});
		return false
		end	
	end
	
	-- if 13 digits long, validate the number
	if is_13long then
	
		--Multiply each of digits by 1 or 3, alternating as you move from left to right, and sum the results.
		--Divide the sum by 10.  The remainder should be 0
		
		local aa = isbn:sub(1, 1);
		local bb = isbn:sub(2, 2) * 3;
		local cc = isbn:sub(3, 3);
		local dd = isbn:sub(4, 4) * 3;
		local ee = isbn:sub(5, 5);
		local ff = isbn:sub(6, 6) * 3;
		local gg = isbn:sub(7, 7);
		local hh = isbn:sub(8, 8) * 3;
		local ii = isbn:sub(9, 9);
		local jj = isbn:sub(10, 10) * 3;
		local kk = isbn:sub(11, 11);
		local mm = isbn:sub(12, 12) * 3;
		local lastdigit = isbn:sub(13, 13);
		
		if lastdigit == "x" or lastdigit == "X" then
			lastdigit = 10;
		end
			
		local sum = aa + bb + cc + dd + ee + ff + gg + hh + ii + jj + kk + mm + lastdigit;
		local remainder = sum % 10;
		
		LogDebug("ISBN Validator > The 13ISBN sum is: " .. tostring(aa) .. "+" .. tostring(bb) .. "+" .. tostring(cc) .. "+" .. tostring(dd) .. "+" .. tostring(ee) .. "+" .. tostring(ff) .. "+" .. tostring(gg) .. "+" .. tostring(hh) .. "+" .. tostring(ii) .. "+" .. tostring(jj) .. "+" .. tostring(kk) .. "+" .. tostring(mm) .. "+" .. tostring(lastdigit) .. "=" .. tostring(sum) .. ". The remainder when " .. sum .. "/10 = " .. remainder);
		
		if remainder == 0 then
			LogDebug("ISBN Validator > The 13 digit ISBN: " .. isbn .. " is valid!");
			return true
		end
		if remainder ~= 0 then
			LogDebug("ISBN Validator > The 13 digit ISBN: " .. isbn .. " is NOT VALID!!");
			ExecuteCommand("AddNote",{transactionNumber, "ISBN Validator > The 13 digit ISBN: " .. isbn .. " is NOT VALID!!"});
			return false
		end	
	end
end


function myerrorhandler( err )

-- This is the error handler for Lending HOLD Request Sender
	local currentTN_int = GetFieldValue("Transaction", "TransactionNumber");
	local transactionNumber = luanet.import_type("System.Convert").ToDouble(currentTN_int);

   --LogDebug("ALMA LENDING REQUEST SENDER build_request ERROR");
   
	if err ~= nil then
	--if err.InnerException ~= nil then
		LogDebug('HTTP Error: ' .. err.InnerException.Message);
			local responseStream = err.InnerException.Response:GetResponseStream();
			local reader = Types["System.IO.StreamReader"](responseStream);
			local responseText = reader:ReadToEnd();
			reader:Close();
			--LogDebug(responseText);
			local errorCode = responseText:match('errorCode>(.-)<'):gsub('(.-)>', '');
			local errorMessage = responseText:match('errorMessage>(.-)<'):gsub('(.-)>', '');
		    LogDebug("Found ALMA errorCode: " .. errorCode .. ": " .. errorMessage);
		
			LogDebug("There was an error executing the ALMA LENDING REQUEST SENDER build_hold_request function.");
			ExecuteCommand("AddNote",{transactionNumber, "Found ALMA Users HOLD Request API errorCode: " .. errorCode .. ": " .. errorMessage});
			SaveDataSource("Transaction");
			--ExecuteCommand("AddNote",{transactionNumber, responseText});
						
			if errorCode ~= nil then
			
			if errorCode == '401136' then
			ExecuteCommand("Route",{transactionNumber, Settings.ItemFailHoldRequestQueue});
			
			else
						
			local error_routing_list = assert(io.open(AddonInfo.Directory .. "\\error_routing.txt", "r"));
			local line_concatenator = "";
			local first_split = "";
			local second_split = "";
			local templine = nil;
				if error_routing_list ~= nil then
					for line in error_routing_list:lines() do
					line_concatenator = line_concatenator .. " " .. line;
						if string.find(line, errorCode) ~= nil then
							first_split,second_split = line:match("(.+),(.+)");
							Alma_error_code = first_split;
							ILLiad_routing_queue = second_split;
				
							LogDebug("The Alma error code for routing is: " .. Alma_error_code);
							LogDebug("The transaction with the Alma error is being routed to: " .. second_split);
							ExecuteCommand("Route",{transactionNumber, second_split});
							break;
						end

					end
					if string.find(line_concatenator, errorCode) == nil then
					

							ExecuteCommand("AddNote",{transactionNumber, "There was an error in the Alma_API from the build_hold_request_sender function."});
							ExecuteCommand("Route",{transactionNumber, Settings.ItemFailHoldRequestQueue});		

				error_routing_list:close();
				end
			end
			
		end
	--end
	--if (IsType(err, "System.Exception")) then
		--return nil, 'Unable to handle error. ' .. err.Message;
	--else
		--return nil, 'Unable to handle error.';
	--end
	end
	end
	
end

function rerun_checker()
    local has_it_run = false;
	local currentTN_int = GetFieldValue("Transaction", "TransactionNumber");
	local transactionNumber = luanet.import_type("System.Convert").ToDouble(currentTN_int);
	
	local connection = CreateManagedDatabaseConnection();
	connection.QueryString = "SELECT TransactionNumber FROM Notes WHERE TransactionNumber = '" .. transactionNumber .. "' AND NOTE = 'The ALMA LENDING REQUEST SENDER Addon: " .. Settings.AddonWorkerName .. " ran on this transaction.'";
	connection:Connect();
	local rerun_status = connection:ExecuteScalar();
	connection:Disconnect();
	if rerun_status == transactionNumber then
		LogDebug('The ALMA LENDING REQUEST SENDER already ran on transaction ' .. transactionNumber .. '. Now Stopping Addon.');
		if Settings.ItemFailHoldRequestQueue ~= "" then
			ExecuteCommand("Route",{transactionNumber, Settings.ItemFailHoldRequestQueue});
			ExecuteCommand("AddNote",{transactionNumber, "ERROR: The ALMA LENDING REQUEST SENDER Addon: " .. Settings.AddonWorkerName .. " already ran on this transaction and it has been sitting in the " .. Settings.ItemSearchQueue .. " processing queue. The TN is being routed to " .. Settings.ItemFailHoldRequestQueue .. ". Please remove the note that says 'The ALMA LENDING REQUEST SENDER Addon: " .. Settings.AddonWorkerName .. " ran on this transaction.' and re-route the TN to the " .. Settings.ItemSearchQueue .. " queue in order to reprocess the TN."});
		end
		has_it_run = true;	
	end
	return has_it_run;
end

function HandleContextProcessing()

	local currentTN_int = GetFieldValue("Transaction", "TransactionNumber");
	local transactionNumber = luanet.import_type("System.Convert").ToDouble(currentTN_int);
	local RequestType = GetFieldValue("Transaction", "RequestType");
	local ProcessType = GetFieldValue("Transaction", "ProcessType");
	local real_isbn = GetFieldValue("Transaction", "ISSN");

	if ProcessType ~= "Borrowing" then
			if rerun_checker() == false then
				ExecuteCommand("AddNote",{transactionNumber, "The ALMA LENDING REQUEST SENDER Addon: " .. Settings.AddonWorkerName .. " ran on this transaction."});
				local good_isbn = validate_isbn(real_isbn);
				if good_isbn then
					local messageSent = false;
					local response;
	
					messageSent, response = pcall(build_hold_request);
			
					if (messageSent == false) then
						LogDebug('There was an error in the Alma_API from the build_hold_request function.  Sending to error handler.');		
						return myerrorhandler(response);		
					else
						LogDebug('ALMA LENDING REQUEST SENDER executed successfully.');
					end
				end	
				
				if not good_isbn then

					local fixed_isbn = extract_isbn(real_isbn)
					local messageSent2 = false;
					local response2;
					
					if fixed_isbn ~= false then
	
					messageSent2, response2 = pcall(build_hold_request);
			
						if (messageSent2 == false) then
							LogDebug('There was an error in the Alma_API from the build_hold_request function with extracted ISBN.  Sending to error handler.');		
							return myerrorhandler(response2);		
						else
							LogDebug('ALMA LENDING REQUEST SENDER executed successfully.');
						end
					end
					if fixed_isbn == false then
						ExecuteCommand("AddNote",{transactionNumber, "Unable to extract ISBN from " .. real_isbn});
						ExecuteCommand("Route",{transactionNumber, Settings.NoISBNandNoOCLCNumberReviewQueue});
					end
				end
			end	
	end
end

function check_excluder(shelving_location)
LogDebug("Initializing function check_excluder");
local currentTN = GetFieldValue("Transaction", "TransactionNumber");
local transactionNumber_int = luanet.import_type("System.Convert").ToDouble(currentTN);
	local excluded_locations = assert(io.open(AddonInfo.Directory .. "\\excluded_locations.txt", "r"));
	if excluded_locations ~= nil then
		for line in excluded_locations:lines() do
			--LogDebug(line)
			--if line == shelving_location then
				--LogDebug("We have a match! [" .. shelving_location .. "]");
			--end
			if string.find(line, shelving_location) ~= nil then
				--LogDebug("Message from check_excluder function: The shelving location [" .. shelving_location .. "] is on the Exclude list.");
				ExecuteCommand("AddNote",{transactionNumber_int, "Message from check_excluder function: The shelving location [" .. shelving_location .. "] is on the Exclude list."});
				return true;
			end

		end
	end
end

function check_process_type_router(the_process_type)
local the_process_type = the_process_type;
LogDebug("Initializing function check_process_type_router for process type: [" .. the_process_type .. "]");
local currentTN = GetFieldValue("Transaction", "TransactionNumber");
local transactionNumber_int = luanet.import_type("System.Convert").ToDouble(currentTN);
local first_split = "";
local second_split = "";

	local routing_for_process_types = assert(io.open(AddonInfo.Directory .. "\\process_type_router.txt", "r"));
	if routing_for_process_types ~= nil then
		for line in routing_for_process_types:lines() do
			--LogDebug(line)
			--if line == the_process_type then
				--LogDebug("We have a match! [" .. the_process_type .. "]");
			--end
			if string.find(line, the_process_type) ~= nil then
				first_split,second_split = line:match("(.+),(.+)");
				local process_type_phrase = first_split;
				local process_type_routing_queue_name = second_split;
				LogDebug("Message from check_process_type_router function: The process type [" .. the_process_type .. "] is on the process_type_router.txt file.  Routing TN to " .. process_type_routing_queue_name);				
				ExecuteCommand("AddNote",{transactionNumber_int, "Message from check_process_type_router function: The process type [" .. the_process_type .. "] is on the process_type_router.txt file.  Routing TN to " .. process_type_routing_queue_name });
				ExecuteCommand("Route",{transactionNumber_int, process_type_routing_queue_name});
				return true;
			end

		end
	end
end

function check_item_process_type(MMSID)
local MMSID = MMSID;
local currentTN = GetFieldValue("Transaction", "TransactionNumber");
local transactionNumber_int = luanet.import_type("System.Convert").ToDouble(currentTN);

local bibs_url = Settings.Alma_Base_URL .. "/bibs/" .. MMSID .. "/holdings/ALL/items?limit=10&offset=0&order_by=none&direction=desc&view=brief&apikey=" .. Settings.Alma_Bibs_API_Key;

local bibs_url_for_print = Settings.Alma_Base_URL .. "/bibs/" .. MMSID .. "/holdings/ALL/items?limit=10&offset=0&order_by=none&direction=desc&view=brief&apikey=YOUR_API_KEY";

LogDebug(bibs_url_for_print);

LogDebug("Creating Bibs web client to lookup holdings for MMSID: " .. MMSID);
		local webClient = Types["WebClient"]();
		webClient.Headers:Clear();
		webClient.Headers:Add("Content-Type", "application/xml; charset=UTF-8");
		webClient.Headers:Add("Accept", "application/xml; charset=UTF-8");
		LogDebug("Sending MMSID to retrieve holdings from Bibs API.");
		local responseString = webClient:DownloadString(bibs_url);
				
		if string.find(responseString, 'item link') ~= nil then
		--LogDebug(responseString);
		local process_type = responseString:match('<process_type(.-)</process_type>'):gsub('(.-)>', ''); -- look for process_type
			if process_type ~= "" then
				LogDebug("The item is showing a process_type of [" .. process_type .. "]");
				if process_type == "ILL" then
					LogDebug("Item is currently on Loan through Resource Sharing. Leaving note on transaction: " .. tostring(transactionNumber_int));
					ExecuteCommand("AddNote",{transactionNumber_int, "From ALMA LENDING REQUEST SENDER: Item is currently on Loan through Resource Sharing"});
				end
				
				if check_process_type_router(process_type) then
					return true;
				end
			end		
			if process_type == "" then
				LogDebug("No process_type found. Continue on.");
			end
		end	
end


function build_hold_request_sender(MMSID)
local MMSID = MMSID;
LogDebug("Initializing function build_hold_request_sender for Lending Request with MMSID: " .. MMSID);

local user = "";
local Library_OCLC_Symbol = "";
local pickup_location = "";
local pseudopatron_exists = false;

local currentTN = GetFieldValue("Transaction", "TransactionNumber");
local transactionNumber_int = luanet.import_type("System.Convert").ToDouble(currentTN);
local ILLiad_Lending_Library = GetFieldValue("Transaction", "LendingLibrary");
if ILLiad_Lending_Library == "" then
	ILLiad_Lending_Library = "NOTHING";
end

local first_split = "";
local second_split = "";
local third_split = "";

LogDebug("Reading pseudopatron_crosswalk.txt");
	local pseudopatron_list = assert(io.open(AddonInfo.Directory .. "\\pseudopatron_crosswalk.txt", "r"));
	if pseudopatron_list ~= nil then
		for line in pseudopatron_list:lines() do
			--LogDebug(line)
			--if line == the_process_type then
				--LogDebug("We have a match! [" .. the_process_type .. "]");
			--end
			if string.find(line, "ALL_LIBRARIES") ~= nil then
				first_split,second_split,third_split = line:match("(.+),(.+),(.+)");
				user = second_split;
				pickup_location = third_split;
				LogDebug("Message from pseudopatron_crosswalk: Your Library uses " .. user .. " for all borrowing libraries not individually listed in the pseudopatron_crosswalk.txt file. The user value '" .. user .. "' is listed after the comma after 'ALL_LIBRARIES'. The pickup_location is: " .. pickup_location);
				pseudopatron_exists = true;
			end		
			
			if string.find(line, ILLiad_Lending_Library) ~= nil then
				first_split,second_split,third_split = line:match("(.+),(.+),(.+)");
				Library_OCLC_Symbol = first_split;
				user = second_split;
				pickup_location = third_split;
				LogDebug("Message from pseudopatron_crosswalk: Your Library uses a crosswalk for OCLC Symbols and pseudopatrons. The OCLC Symbol for this request is " .. Library_OCLC_Symbol .. " and the corresponding pseudopatron name is " .. user .. ". The pickup_location is: " .. pickup_location);	
				pseudopatron_exists = true;				
			end
			
			local pickup_location_type = "LIBRARY";
			if pickup_location == "Home Delivery" then
				pickup_location_type = "USER_HOME_ADDRESS";
			end
			if pickup_location == "Office Delivery" then
				pickup_location_type = "USER_WORK_ADDRESS";
			end

		if pseudopatron_exists ~= true then
			LogDebug("There are no matching pseudopatron. Please check your pseudopatron_crosswalk.txt file.");	
			ExecuteCommand("AddNote",{transactionNumber_int, "There are no matching pseudopatrons. Please check your pseudopatron_crosswalk.txt file and make sure that there is a accurate: ALL_LIBRARIES,alma_lending_user,alma_library_pickup_location OR have individually listed (1)OCLC_Symbol; (2)username for Lending Transaction in Alma; (3)Alma Pickup Location.  Example for SUNY Geneseo: ALL_LIBRARIES,alma_lending_user,GENMN or NAM,SUNYAlbany,GENMN"});
		end


LogDebug("The pseudopatron has been determined");

-- Get the user's matching pickup location and pickup location institution by using the sublibraries.txt crosswalk file	
-- Remove the sublibraries crosswalk and add a third cataegory to the pseudopatron_crosswalk document that would contain the pickup location.  This would be the same library codes that are in the sublibraries.txt file. 


	
-- Assemble XML hold message to send to API


local hold_message = '<?xml version="1.0" encoding="ISO-8859-1"?><user_request><request_type>HOLD</request_type><pickup_location_type>' .. pickup_location_type .. '</pickup_location_type><pickup_location_library>' .. pickup_location .. '</pickup_location_library><pickup_location_institution>' .. Settings.Alma_Institution_Code .. '</pickup_location_institution></user_request>';
--LogDebug("The Hold Message sent to Alma is: " .. hold_message);
if Settings.UltimateDebug then
	ExecuteCommand("AddNote",{transactionNumber_int, "UltimateDebug > Alma API Hold Message: " .. hold_message});
end

-- Assemble URL for connecting to Users API
local alma_url = Settings.Alma_Base_URL .. '/users/' .. user .. '/requests?user_id_type=all_unique&mms_id=' .. MMSID .. '&allow_same_request=false&apikey=' .. Settings.Alma_Users_API_Key;
local alma_url_for_message = Settings.Alma_Base_URL .. '/users/' .. user .. '/requests?user_id_type=all_unique&mms_id=' .. MMSID .. '&allow_same_request=false&apikey=YOUR_KEY'; 

if Settings.UltimateDebug then
	ExecuteCommand("AddNote",{transactionNumber_int, "UltimateDebug > Alma API URL for Hold Message: " .. alma_url_for_message});
end
	
		LogDebug("Hold Message prepared for sending: " .. hold_message);
		LogDebug("Alma URL prepared for connection: " .. alma_url_for_message);
		LogDebug("Creating web client for Alma HOLD message.");
		local webClient = Types["WebClient"]();
		webClient.Headers:Clear();
       	webClient.Headers:Add("Content-Type", "application/xml; charset=UTF-8");
		webClient.Headers:Add("accept", "application/xml; charset=UTF-8");
		LogDebug("Sending Hold Message to Alma Users API.");
				
		local responseString = webClient:UploadString(alma_url, hold_message);

		if string.find(responseString, "<user_request>") then
			LogDebug("No Problems found in Alma Users HOLD API Response.");
			ExecuteCommand("Route",{transactionNumber_int, Settings.ItemSuccessHoldRequestQueue});
			ExecuteCommand("AddNote",{transactionNumber_int, "Alma API Response for HOLD received successfully"});
			--ExecuteCommand("AddNote",{transactionNumber_int, "Alma API Successful Response: " .. responseString});
			SaveDataSource("Transaction");	
			return true;
		end	
		end -- end pseudopatron_crosswalk for loop
	end -- end pseudopatron_crosswalk lookup
end -- end function

function analyze_ava_tag(responseString)
LogDebug("Initializing function analyze_ava_tag");
	local is_record_found = false;
	local is_item_available = false;
	local is_location_permitted_for_use = false;
	local use_record = true;
	local currentTN_int = GetFieldValue("Transaction", "TransactionNumber");
	local transactionNumber_int = luanet.import_type("System.Convert").ToDouble(currentTN_int);

		if string.find(responseString, '<datafield ind1=" " ind2=" " tag="AVA">') ~= nil then	
		local mmsid_list = "";
		local is_item_available = false;
			for ava_blocks in string.gmatch(responseString, '<datafield ind1=" " ind2=" " tag="AVA">(.-)</datafield>') do -- for every AVE tag block, do the following
				if string.find(ava_blocks, '<subfield code="0">') ~= nil then  --if the block has an MMSID then
					-------------DETERMINING MMSID-------------
					local MMSID = ava_blocks:match('<subfield code="0">(.-)<'):gsub('(.-)>', ''); -- look for MMSID
					LogDebug("MMSID: " .. MMSID);		
					local mmsid_list = MMSID .. "," .. mmsid_list;
	
					-------------DETERMINING AVAILABILITY-------------
					local availability_message = ava_blocks:match('<subfield code="e">(.-)<'):gsub('(.-)>', ''); -- look for availability in subfield e
					LogDebug("availability_message: " .. availability_message);
					if availability_message == "unavailable" or availability_message == "Unavailable" then
						use_record = false;
						is_item_available = false;
						LogDebug("The MMSID: " .. MMSID .. " is showing as " .. availability_message);
						LogDebug("Preparing to connect to Bibs API to determine if there is a process_type (e.g., MISSING)");
						if check_item_process_type(MMSID) then		
							return true;
						end
					
					end
					if availability_message == "Available" or availability_message == "available" then
						LogDebug("The MMSID: " .. MMSID .. " is showing as " .. availability_message);
						is_item_available = true;
					end
					-------------DETERMINING LOCATION-------------
					local shelving_location = "";
					if string.find(ava_blocks, '<subfield code="c">') ~= nil then -- if the block has a location (in subfield m) then get location, else skip location retrieval
						shelving_location = ava_blocks:match('<subfield code="c">(.-)<'):gsub('(.-)>', '');			
						LogDebug("Location: " .. shelving_location);
						local check_excluder_return = check_excluder(shelving_location)
						if check_excluder_return then
						is_location_permitted_for_use = false;
						use_record = false;
						LogDebug("[The location: [" .. shelving_location .. "] is on the exclude list. Skipping record.");
						end
						if not check_excluder_return then
							is_location_permitted_for_use = true;
							LogDebug("This location permitted for Holds and Borrowing: [" .. shelving_location .. "]");							
							if is_item_available then
								use_record = true;
							end
						end			
					end
					if string.find(ava_blocks, '<subfield code="c">') == nil then  -- if it cannot find subfield c, leave a note
						LogDebug("From Alma SRU > Cannot Determine Location.  The <subfield code='c'> is blank in the AVE tag from the SRU return.");
						is_location_permitted_for_use = true;
					end	

					if is_item_available and is_location_permitted_for_use then
						is_record_found = true;
						LogDebug("Found available item for MMSID: " .. MMSID);
						if build_hold_request_sender(MMSID) then
							return true;
						end
					end				
				end --if the block has an MMSID then
			end -- for loop
			if use_record == false then
			LogDebug("No Available items found for MMSID record(s): " .. mmsid_list:sub(1, -2));
				if is_location_permitted_for_use == false then
					ExecuteCommand("Route",{transactionNumber_int, Settings.ItemInExcludedLocationNeedsReviewQueue});
					ExecuteCommand("AddNote",{transactionNumber_int,"The location is on the exclude list. Routing to Review Queue."});
					return true;
				end
				if is_location_permitted_for_use == true then
					if Settings.EnableSendingBorrowingRequests == true then
					LogDebug("The item is currently checked out.");
						--build_request()
					end
					if Settings.EnableSendingBorrowingRequests == false then
						LogDebug("EnableSendingHoldRequests is set to false and there are no available items for a Hold Request. Routing TN to failure queue.");
						ExecuteCommand("AddNote",{transactionNumber_int,"The item is currently checked out. Sending Borrowing Requests is disabled in the config.  Routing to failure queue."});
						if Settings.ItemFailHoldRequestQueue ~= "" then
							ExecuteCommand("Route",{transactionNumber_int, Settings.ItemFailHoldRequestQueue});
							return true;
						end
					end
				end				
			end
		end -- if AVA tag		
end -- function

function build_hold_request()
LogDebug("Initializing function build_hold_request");
local currentTN = GetFieldValue("Transaction", "TransactionNumber");
local transactionNumber_int = luanet.import_type("System.Convert").ToDouble(currentTN);

local isbn = GetFieldValue("Transaction", "ISSN");
local oclc_number = GetFieldValue("Transaction", "ESPNumber");

local used_oclc_number = false;
local used_isbn = false;

local sru_url = "";
local records_found = "";
local responseString = "";

if isbn == "" and oclc_number == "" then
	LogDebug("No ISBN or OCLC Number found in Transaction.  Please add the ISBN or OCLC Number and reprocess Transasction.");
	-- Route for review (put config in for queue name)
	ExecuteCommand("Route",{transactionNumber_int, Settings.NoISBNandNoOCLCNumberReviewQueue});
	return true;
end


local last_piece_of_Full_Alma_URL = string.sub(Settings.Full_Alma_URL, -3);
if last_piece_of_Full_Alma_URL ~= "com" then
	ExecuteCommand("AddNote",{transactionNumber_int,"ERROR: Please update your Addon config value for Full_Alma_URL.  Your Full_Alma_URL should end in .com without a slash at the end of the URL."});
	LogDebug("ERROR: Please update your Addon config value for Full_Alma_URL.  Your Full_Alma_URL should end in .com without a slash at the end of the URL.");
end


--local sru_url_isbn = "https://suny-gen.alma.exlibrisgroup.com/view/sru/01SUNY_GEN?version=1.2&operation=searchRetrieve&recordSchema=marcxml&query=alma.isbn=" .. isbn .. "&maximumRecords=3";

if oclc_number ~= "" then
	sru_url = Settings.Full_Alma_URL .. "/view/sru/" .. Settings.Alma_Institution_Code .. "?version=1.2&operation=searchRetrieve&recordSchema=marcxml&query=alma.oclc_control_number_035_a=" .. oclc_number .. "&maximumRecords=3";
	used_oclc_number = true;
end

if isbn ~= "" then 
	sru_url = Settings.Full_Alma_URL .. "/view/sru/" .. Settings.Alma_Institution_Code .. "?version=1.2&operation=searchRetrieve&recordSchema=marcxml&query=alma.isbn=" .. isbn .. "&maximumRecords=3";
	used_isbn = true;
	used_oclc_number = false;
end

LogDebug(sru_url);
if Settings.UltimateDebug then
	ExecuteCommand("AddNote",{transactionNumber_int, "UltimateDebug > Alma SRU Lookup URL: " .. sru_url});
end

	if used_isbn then
		LogDebug("Creating SRU web client to lookup ISBN: " .. isbn);
		local webClient = Types["WebClient"]();
		webClient.Headers:Clear();
		webClient.Headers:Add("Content-Type", "application/xml; charset=UTF-8");
		webClient.Headers:Add("Accept", "application/xml; charset=UTF-8");
		LogDebug("Sending ISBN to Retrieve MMSID.");
		responseString = webClient:DownloadString(sru_url);
		--LogDebug(responseString);
		
		records_found = responseString:match('numberOfRecords>(.-)<'):gsub('(.-)>', '');
		--LogDebug(records_found);
	end
	
	if used_oclc_number then
		LogDebug("Creating SRU web client to lookup OCLC Number: " .. oclc_number);
		local webClient = Types["WebClient"]();
		webClient.Headers:Clear();
		webClient.Headers:Add("Content-Type", "application/xml; charset=UTF-8");
		webClient.Headers:Add("Accept", "application/xml; charset=UTF-8");
		LogDebug("Sending OCLC Number to Retrieve MMSID.");
		responseString = webClient:DownloadString(sru_url);
		--LogDebug(responseString);	
		records_found = responseString:match('numberOfRecords>(.-)<'):gsub('(.-)>', '');
		--LogDebug(records_found);
	end
			
	if records_found ~= "0" then		
		if used_isbn then
			LogDebug("This number of records were found for ISBN " .. isbn .. ": " .. records_found);
		end
		if used_oclc_number then
			LogDebug("This number of records were found for OCLC Number " .. oclc_number .. ": " .. records_found);
		end
				
		if analyze_ava_tag(responseString) ~= true then
			LogDebug("The AVA lookup did not return any available items to create a Hold request.");
			ExecuteCommand("AddNote",{transactionNumber_int,"From ALMA LENDING REQUEST SENDER: The AVA lookup showed available records but did not return any available items to create a Hold request. Routing to: " .. Settings.ItemFailHoldRequestQueue});
			ExecuteCommand("AddNote",{transactionNumber_int,responseString});
			LogDebug(responseString);
			ExecuteCommand("Route",{transactionNumber_int, Settings.ItemFailHoldRequestQueue});
		end
	end -- if records found is not zero		

	if records_found == "0" then
		LogDebug("There are 0 local holdings for this item. Unable to place hold request for Lending Library. Routing TN to: " .. Settings.ItemFailHoldRequestQueue);
		ExecuteCommand("AddNote",{transactionNumber_int,"There are 0 local holdings for this item. Unable to place hold request for Lending Library. Routing TN to: " .. Settings.ItemFailHoldRequestQueue});
		ExecuteCommand("Route",{transactionNumber_int, Settings.ItemFailHoldRequestQueue});	
		return true;
	end -- if records_found == "0"
end -- function