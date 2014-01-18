<cfcomponent displayname="WADL Generator" output="false" hint="Generates a WADL file from DocGenerator (META) (Apigee Console - apigee tags">

	<!--- This function is used to reload the component if any functions are modified --->
    <cffunction name="init" output="false">

    	<cfargument name="docGenerator" type="string" required="true">
		<cfargument name="Relaxation" type="component" required="true">

		<cfset variables.dc = createObject("component", arguments.docGenerator)>
		<cfset variables.dc = dc.setRelaxation(arguments.Relaxation)>

        <cfreturn this>
    </cffunction>


    <!--- generate WADL file --->
		
	<cffunction name="generateWADL" output="false">

		<cfargument name="basePath" type="string" required="true">
		<cfargument name="docPath" type="string" required="true">
		<cfargument name="emailTo" type="string" required="false">

		<cfscript>
			variables.meta = variables.dc.getFullMeta();	
		</cfscript>

		<!--- automate a quick email to test data being returend via getFullMeta --->
		<cfif isDefined("arguments.emailTo")>
			<cfmail to="#arguments.emailTo#" from="#arguments.emailTo#" subject="wadlGenerator.getFullMeta()" type="html">
				<cfdump var="#variables.meta#">
			</cfmail>
		</cfif>

		<cfoutput>

		<cfxml variable="wadlFile"> 
		    <application xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:apigee="http://api.apigee.com/wadl/2010/07/" xmlns="http://wadl.dev.java.net/2009/02" xsi:schemaLocation="http://wadl.dev.java.net/2009/02 http://apigee.com/schemas/wadl-schema.xsd http://api.apigee.com/wadl/2010/07/ http://apigee.com/schemas/apigee-wadl-extensions.xsd">
		        
		        <!-- Base defines the domain and base path of the endpoint -->
		        <resources base="#arguments.basePath#">

		        <cfset loopCount = 1>
		        <cfloop array="#variables.meta#" index="i">

		            <resource path="#i.pattern#">
		            <!-- Resources that are the same but have multiple verbs can have multiple method items in the WADL.  -->
		            <param name="userToken" required="false" type="xsd:string" style="header" default="0">
		            	<doc>All methods acitng on behalf of a User must include the userToken (unique ID for Application/User)</doc>
		            </param>

		                <!-- 
		                Each <resource> element can contain zero or more optional <param> elements that define parameters. If included, these parameters are used by methods defined as part of this <resource> element. 
		                -->
		               <!---  <param default="json" name="format" required="true" style="template" type="xsd:string">
		                    <doc>json or xml format</doc>
		                    <option mediaType="application/json" value="json"/>
		                    <option mediaType="application/xml" value="xml"/>
		                </param> --->

		            <cfloop array="#i.verbs#" index="v">

		                <!--  Methods should each have a unique id. | attribute displayName controls appearance in Console  -->
		                <method id="method#loopCount#" name="#v.verb#" apigee:displayName="#structKeyExists(v,"apigeeName") ? v.apigeeName : i.pattern#">

		                    <!-- Tags are used to organize the list of methods. Primary tag will list the default placement. -->
		                    <apigee:tags>
		                        <apigee:tag primary="true">#structKeyExists(v, "apigeeCat") ? v.apigeeCat : listFirst(i.pattern, "/")#</apigee:tag>
		                    </apigee:tags>

		                    <!--  Is authentication required for this method?  -->
		                    <apigee:authentication required="true"/>

		                    <!-- The content of the doc element is shown as a tooltip in the Console's method list. (customize link/naming convention as needed)  -->
		                    <doc apigee:url="#arguments.docPath#/#structKeyExists(v,"apigeeName") ? v.apigeeName : v.name#">#structKeyExists(v,"apigeeDoc") ? XmlFormat(v.apigeeDoc) : XmlFormat(v.hint)#</doc>

		                    <!-- REQEUST element contains parameters specifically for this method -->
		                    <request>

		                    	<!--- 
		                    		Parameter Output
		                    		* POST/PUT within payload representation (except when part of template)
		                    		* GET/DELETE standard query 
		                    	--->

		                    	<!--- create default structure to hold payload paramaters --->
		                    	<cfset payload = {}>

		                    	<!---- loop over parameters --->
		                    	<cfloop array="#v.parameters#" index="p">
		                    		
		                    		<cfif findNoCase(p.name, i.pattern) OR (v.verb NEQ "POST" AND v.verb NEQ "PUT")>

		                    			<!--- reset REQUIRED if part of pattern (template params should be required) --->
		                    			<cfif findNoCase(p.name, i.pattern)><cfset p.required =  true></cfif>

		                    			<!--- parameter is part of the template (pattern) OR not part of POST/PUT method --->	
		                    			<param name="#p.name#" required="#p.required#" type="xsd:#p.type#" style="query" default="#structKeyExists(p, "default") ? p.default : ""#">
				                			<doc>#structKeyExists(p, "hint") ? p.hint : ""#</doc>
				                		</param>

				                	<cfelse>

				                		<!--- parameter is NOT part of pattern and is either POST or PUT --->
				                		<cfset payload[p.name] = structKeyExists(p, "default") ? p.default : '' >

		                    		</cfif>
		                    	</cfloop>

		                    	<!--- if we have any valid payload parameters, serialize to JSON and include representation --->
		                    	<cfif structCount(payload) GTE 1>

		                    		<!--- serialize the payload to JSON --->
			                    	<cfset local.cdata = serializeJSON(payload)>

			                    	<!--- include the payload representation --->
			                    	<representation mediaType="application/json"> 
								        <apigee:payload required="true">
								           <doc apigee:url="http://api.mydomain.com/doc/resource/method">
								               Content description.
								           </doc>
								           <apigee:content>
								                <![CDATA[ 
								                    #local.cdata#         
								                ]]>
								           </apigee:content>
								        </apigee:payload>
								    </representation>

		                    	</cfif>
			                    	

		                    	<!--- <representation mediaType="application/json"> 
							        <apigee:payload required="true">
							           <doc apigee:url="http://api.mydomain.com/doc/resource/method">
							               Content description.
							           </doc>

							           <cfset st = {}>
							           <cfloop array="#v.parameters#" index="p">
							           		<cfset st[p.name] = structKeyExists(p, "default") ? p.default : '' >
							           </cfloop>
							           <cfset local.cdata = serializeJSON(st)>

							           <apigee:content>
							                <![CDATA[ 
							                    #local.cdata#         
							                ]]>
							           </apigee:content>
							        </apigee:payload>
							    </representation> --->


		                    	<!--- (POST/PUT) wrap parameters in representation tag , otherwise API passes as query params and can cause URI error (too long, etc.) --->
		                    	<!--- <cfif v.verb EQ "POST" OR v.verb EQ "PUT">
		                    		<representation mediaType="application/x-www-form-urlencoded"> 	
		                    	</cfif>
		                    	

				                <cfloop array="#v.parameters#" index="p">

				                	<param name="#p.name#" required="#p.required#" type="xsd:#p.type#" style="query" default="#structKeyExists(p, "default") ? p.default : ""#">
				                		<doc>#structKeyExists(p, "hint") ? p.hint : ""#</doc>
				                	</param>

				                </cfloop> ---> <!-- end PARAMETER loop -->


			                	<!--- wrap parameters in representation tag (POST/PUT), consider modifying for query params --->
		                    	<!--- <cfif v.verb EQ "POST" OR v.verb EQ "PUT">
		                    		</representation> 	
		                    	</cfif> --->

		                	</request>

		                </method>

		            <cfset loopCount = loopCount + 1>
		            </cfloop> <!-- end VERB loop -->

		            </resource>

		        </cfloop> <!-- END META loop -->


		        </resources>

		    </application>
		</cfxml> 

		</cfoutput>

		<!--- return the generated file --->
		<cfreturn wadlFile>

	</cffunction>


</cfcomponent>