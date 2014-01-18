<!--- EXAMPLE API REST AUTHENTICATION --->

	<cffunction name="apiAuthenticate" access="public" output="false" hint="validates if request to API is authorized">

		<cfargument name="apiResource" type="any">

		<cfscript>

		// savecontent variable="content" { writeDump(arguments); }
      	// mail = new mail();
      	// mail.setSubject("apiAuth MAIL");
      	// mail.setTo("email@domain.com");
     	// mail.setFrom ("email@domain.com");
     	// mail.addPart(type="html", charset="utf-8", body=content);
     	// mail.send();

     	// default response structure
     	var response = {
     		"success" = "",
     		"error" = "",
     		"errorMessage" = "",
     		"X-RateLimit-Limit" = "",
     		"X-RateLimit-Remaining" = "",
     		"X-RateLimit-Reset" = ""
		};

			// BASIC AUTHENTICATION - is required for all REST calls

			httpHeaders = getHTTPRequestData().headers;

			if (!structKeyExists (httpHeaders, "Authorization")) {
				// user did not submit any authorization, return 401 status code "unauthorized"
				response.success = false;
				response.error = "UnAuthorized";
				response.errorMessage = "Please include your Authorization Credentials on all requests";
				
				return response;

			} else {
				// BASIC AUTHENTICATION VALIDATION WORKFLOW (always use SSL for connection with Basic Auth)

				// get encoded credentials from HTTP request headers
				local.encodedCredentials = ListLast(httpHeaders.Authorization, " " );

				// convert encoded credentials from base64 to binary and back to string
				local.credentials = ToString(ToBinary( local.encodedCredentials ));

				// set credentials to unique variables
				local.api.apiKey = ListFirst( local.credentials, ":" );
				local.api.apiSecret = ListRest( local.credentials, ":" );
				
				// userToken must be passed as part of method call, if it exists set it
				param name="httpHeaders.userToken" default="";
				IF (len(httpHeaders.userToken) GTE 1) { local.api.privateKey = httpHeaders.userToken; }

				// build dataStructure for cfeoSPB
				st = {};

				// loop over arguments and try to set the variables for the storedProc call
				structEach(local.api, function(key,value) {
					try {
						st[key] = value;
					} catch (any e) {
						// error code goes here
					}
				});
					
				// call cfeoSPB (call via beanFactor because apiAuthenticate does not recognize injectors)
				local.appRole = application.beanFactory.getBean("cfeoSPB").callSP("getApplicationRole", st, "1"); // or std. cfquery to authenticate
				rsApp = local.appRole.rs1;

				// BASIC AUTHENTICATION CREDENTIALS VALIDATION

				if (rsApp.recordCount GTE 1) {
					// set the Application Role returned from the call
					local.app.role = rsApp.role;
				} else {
					// APP credentials did not return a valid Applications (deny request)

					response.success = false;
					response.error = "NotAuthorized";
					response.errorMessage = "Please check your Authorization Credentials";

					return response;
				}

			}
			// basic authentication has been provided & successfull to reach this stage

			
			// X-RateLimit Validation (if request exceeds lmits deny request)

			// does apiRateCache not exist OR is it older than 1 hour and need to be created/recreated
			if (!structKeyExists(application, "apiRateCache") OR dateDiff("s", application.apiRateCache.createdAt, now()) GT 3600 ) { 
				application.apiRateCache = {};
				application.apiRateCache["createdAt"] = now();
			}

			// does the apiRateCache have a record for the current application or do we create it
			if (!structKeyExists(application.apiRateCache, local.api.apiKey)) {
				application.apiRateCache[local.api.apiKey] = 1;
			} else {
				application.apiRateCache[local.api.apiKey] = structFind(application.apiRateCache, local.api.apiKey) + 1;
			}

			// set the current Application requests
			local.apiRequests = application.apiRateCache[local.api.apiKey];

			// add the current rate limit in effect
			response["X-RateLimit-Limit"] = rsApp.rateLimitHour;

			// add the request limit remaining in the current timeframe
			response["X-RateLimit-Remaining"] = max( (rsApp.rateLimitHour - local.apiRequests) , 0 ) ;

			// add the current timeframe (seconds) until the rate limit will be reset
			response["X-RateLimit-Reset"] = dateDiff("s",  now(), dateAdd("n", "60", application.apiRateCache.createdAt));


			// does the current request exceed the Applications allowed rate limit
			if ( local.apiRequests GT rsApp.rateLimitHour ) {
				response.success = false;
				response.error = "rateLimit";
				response.errorMessage = "You are only allowed #rsApp.rateLimitHour# requests per hour";

				return response;
			} else {
				// OPTIONAL:  log the API request against the Application usage

				// build dataStructure for cfeoSPB or std. cfquery to log
				st = {};
				st.applicationID = rsApp.applicationID;
				st.method = apiResource.method;
				st.path = apiResource.path;
				st.pattern = apiResource.pattern;
				st.role = apiResource.role;
				st.verb = apiResource.verb;
				st.timePeriod = now();
				st.requests = '1';

				// set the UTC server date for submitting data
				st.utcServer = application.beanFactory.getBean("udf").setUTCtz(now(), 'to');  // or std. dateTime

				// call cfeoSPB (call via beanFactor because apiAuthenticate does not recognize injectors)
				local.setApplicationUsage.response = application.beanFactory.getBean("cfeoSPB").callSP("setApplicationUsage", st, "1"); // or std. cfquery
				local.setApplicationUsage.response = application.beanFactory.getBean("cfeoSPB").callSP("setApplicationUsageCount", st, "1"); // or std. cfquery
			}


			// EXAMPLE AUTHENTICATION WORKFLOW

			/*
				e.g. from RestConfig.json.cfm
				"/user/{userAccountID": {
				"GET": {
		        "Bean": "user",
		        "Method": "userGET",
		        "apigeeName": "getUserByID",
		        "apigeeDoc": "Gets user data",
		        "Role": "user:userAccountID"		<-- looking at the ROLE ("user") and the value to authenticate that user has access to
		      	}
		      }
			*/

			
			// authenticate initially based on APPLICATION ROLE
			switch (local.app.role) {

				case "admin": 

					// App Role of admin is granted request automatically
					response.success = true;

					return response;

					break;

				case "user": 

					// App Role of user must validate against the method role

					// METHOD ROLE - define the method role & authentiation  
			

					local.method.role = listFirst(apiResource.role, ":");

					if (listLen(apiResource.role, ":") GTE 2) {
						local.method.auth = listRest(apiResource.role, ":");
					}


					switch (local.method.role) {

						case "admin":

							// Method Role of admin is denied request automtically as App has wrong role
							response.success = false;
							response.error = "NotAuthorized";
							response.errorMessage = "";

							return response;
							
							break;

						case "public":

							// Method Role of public is granted request automatically as no App Role is required
							response.success = true;

							return response;

							break;

						case "user":

							// VALIDATE Request (URI data in Path against App Role/Recordset data)

							param name="local.method.auth" default=""; // default param in event RestConfigjson.cfm is incorrectly configured w/out this data

							// find the position of the methodAuth iten in the PATTERN (e.g. /user/{userAccountID})
							local.apiResource.patternPosition = listFindNoCase(apiResource.pattern, "{#local.method.auth#}", "/");

							// find the resource value provided in path (e.g. /user/2345)
							local.apiResource.authValue = listGetAt(apiResource.path, local.apiResource.patternPosition, "/");


							// get the CSV list of authenticated values (e.g. groupIDs, eventIDs, etc.)
							local.app.authValues = rsApp[local.method.auth];


							// validate if the Application/User is authenticated for that resource
							local.auth.result = listFindNoCase(local.app.authValues, local.apiResource.authValue);

							if (local.auth.result EQ 0) {
								// authValue NOT found within local.app.authValues
								response.success = false;
								response.error = "notAuthorized";
								response.errorMessage = "";

								return response;

							} else {
								// authValue FOUND within local.app.authValues
								response.success = true;

								return response;

							}

							break;

						default:

							response.success = false;
							response.error = "NotAuthorized";
							response.errorMessage = "";

							return response;

							break;

					} // end switch local.method role


					break;

				default:

					response.success = false;
					response.error = "NotAuthorized";
					response.errorMessage = "";

					return response;

					break;
			} // end swtich local.app.role
			
		</cfscript>


	</cffunction>
