# Alma_Lending_Request_Sender
The purpose of this ILLiad Server Addon is to send Lending requests from ILLiad to Alma as Hold requests for a pseudopatron.

_Check out the Alma Borrowing Request Sender wiki for installation instructions:_

https://github.com/Hypolymer/Alma_Lending_Request_Sender/wiki

**This Server Addon was developed by:**
- Bill Jones (SUNY Geneseo)
- Tim Jackson (SUNY Libraries Shared Services)
- Angela Persico (University at Albany)

**A few details about the ILLiad Addon:**
- The purpose of this Addon is to send Lending requests from ILLiad to Alma by creating Hold requests for pseudopatron accounts in Alma that represent ILLiad Borrowing Institutions
- The Addon monitors RequestType: Loan in a configurable ILLiad queue for ProcessType: Lending
- The Addon uses an Alma SRU Lookup to determine availability and to gather item information
- The Addon uses the Bibs API in order to lookup item process_type for unavailable items to determine if MISSING, IN BINDERY, in ILL, or another process_type
- The Addon sends a Hold request to Alma using the Users API 'Create user request' call
- The Addon validates the submitted ISBN and attempts to extract an ISBN from the ILLiad transaction if validation fails

**Text files contained in the Addon for configuration:**
- The Addon uses a file called error_routing.txt to route specific API numerical errors to specific ILLiad queues
- The Addon uses a file called pseudopatron_crosswalk.txt to crosswalk between the ILLiad Borrowing Institution OCLC Symbol, the pseudopatron username, and the Alma Pickup Location code (Example: ALL_LIBRARIES,borrowing_pseudopatron,GENMN)
- The Addon uses a file called process_type_router.txt to route specific process_type values (like MISSING, or IN BINDERY, or RESERVES) to specific queues
- The Addon uses a file called excluded_locations.txt to make specific shelving locations unavailable for Hold requests 
