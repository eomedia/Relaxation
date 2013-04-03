component
	accessors="true"
	displayname="Chill REST Framework"
	hint="I am the Chill. Framework for REST in CF. Relax, I got this!"
	output="false"
{

	property name="BeanFactory" type="component";
	property name="AuthorizationMethod" type="any";
	
	variables.Config = {};
	
	/**
	* @hint "I initialize the object and get the routing all setup."
	* @output false
	**/
	public component function init( required struct Config ) {
		/* Set the Return Format. Default JSON. */
		variables.Config.ReturnFormat = isDefined("arguments.Config.ReturnFormat") ? arguments.Config.ReturnFormat : 'JSON';
		/* Get the pattern matching for resources setup. */
		configureResources( arguments.Config.RequestPatterns );
		
		return this;
	}
	
	/**
	* @hint "I will configure the pattern matching for the different resources."
	* @output false
	**/
	private void function configureResources( required struct Patterns ) {
		variables.Config.Resources = [];
		for ( var key in arguments.Patterns ) {
			var resource = arguments.Patterns[key];
			var resource["Pattern"] = key & ( Right(trim(key),1) EQ '/' ? '' : '/' );
			/* Start building the regex for this pattern. */
			resource.Regex = key;
			/* Add trailing slash to make matching easier. */
			resource.Regex &= ( Right(trim(resource.Regex),1) EQ '/' ? '' : '/' );
			/* Replace the {} sections with capture groups. */
			resource.Regex = '^' & REReplace(resource.Regex, "{[^}]*?}", "([^/]+?)", "all") & '$';
			ArrayAppend(
				variables.Config.Resources
				,resource
			);
		}
	}
	
	/**
	* @hint "Give an resource path and verb, I will return the config object."
	* @output false
	**/
	public struct function findResourceConfig( required string Path, required string Verb ) {
		/* Add trailing slash to make matching easier. */
		arguments.Path &= ( Right(trim(arguments.Path),1) EQ '/' ? '' : '/' );
		var result = {
			"Located": false
			,"Error": ""
			,"Path": ""
			,"Pattern": ""
			,"Regex": ""
		};
		for ( var resource in variables.Config.Resources ) {
			if ( RefindNoCase(resource.Regex,arguments.Path) ) {
				var match = resource;
			}
		}
		if ( IsNull(match) ) {
			result.Error = "ResourceNotFound";
		} else {
			if ( !StructKeyExists(match, arguments.Verb) ) {
				result.Error = "VerbNotFound";
			} else {
				result.Located = true;
				result.Regex = match.Regex;
				result.Pattern = match.Pattern;
				result.Path = arguments.Path;
				StructAppend(result, match[arguments.Verb]);
			}
		}
		return result;
	}
	
	/**
	* @hint "I will gather all the request arguments up from the possible sources. (URL, Form, URI, Request Body)"
	* @output false
	**/
	public struct function gatherRequestArguments( required struct ResourceMatch, string RequestBody = "", struct URLScope = {}, struct FormScope = {} ) {
		var args = {};
		/* Coalesce all the sources together. */
		StructAppend(args, URLScope, false);
		StructAppend(args, FormScope, false);
		if ( len(trim(arguments.RequestBody)) && isJSON(arguments.RequestBody) ) {
			StructAppend(args, DeserializeJSON(arguments.RequestBody), false);
		}
		/* Get the arguments from the URIs (e.g. /product/321/colors/red/) */
		if ( ReFindNoCase("[{}]", ResourceMatch.Pattern) ) {
			var nameLenPos = RefindNoCase(ResourceMatch.Regex, ResourceMatch.Pattern, 1, true);
			var valueLenPos = RefindNoCase(ResourceMatch.Regex, ResourceMatch.Path, 1, true);
			if ( ArrayLen(nameLenPos.Len) == ArrayLen(valueLenPos.Len) && ArrayLen(valueLenPos.Len) > 1 ) {
				for ( var i = 2; i <= ArrayLen(nameLenPos.Len); i++ ) {
					var argName = ReReplaceNoCase(mid(ResourceMatch.Pattern, nameLenPos.Pos[i], nameLenPos.Len[i]), "[{}]", "", "all");
					args[argName] = mid(ResourceMatch.Path, valueLenPos.Pos[i], valueLenPos.Len[i]);
				}
			}
		}
		return args;
	}
	
	/**
	* @hint "I will handle a REST request. Given the requested path and verb, I will call the correct resource and method."
	* @output false
	**/
	public struct function handleRequest( required string Path, string Verb, string RequestBody, struct URLScope, struct FormScope ) {
		/* Try to get reasonable defauls set. */
		if ( isNull(arguments.URLScope) && isDefined("URL") && isStruct(URL) ) {
			arguments.URLScope = URL;
		}
		if ( isNull(arguments.FormScope) && isDefined("FORM") && isStruct(FORM) ) {
			arguments.FormScope = FORM;
		}
		if ( isNull(arguments.RequestBody) && isJSON(GetHttpRequestData().Content) ) {
			arguments.RequestBody = GetHttpRequestData().Content;
		}
		if ( isNull(arguments.Verb) ) {
			arguments.Verb = CGI.REQUEST_METHOD;
		}
		var result = {
			"Success": true
			,"Output": ""
			,"Error": ""
			,"ErrorMessage": ""
		};
		var resource = findResourceConfig( argumentCollection = arguments );
		if ( !resource.Located ) {
			/* We could not locate the configuration for handling this type of request. */
			result.Success = false;
			result.Error = resource.Error;
			if ( resource.Error == "ResourceNotFound" ) {
				result.ErrorMessage = "A resource to handle the pattern (#arguments.Path#) could not be found.";
			} else if ( resource.Error == "VerbNotFound" ) {
				result.ErrorMessage = "The resource (#arguments.Path#) is not configured to handle (#arguments.Verb#) requests.";
			}
			return result;
		}
		if ( !isNull(getAuthorizationMethod()) ) {
			var authorize = getAuthorizationMethod();
			if ( !authorize(resource) ) {
				result.Success = false;
				result.Error = "NotAuthorized";
			}
		}
		var bean = getBeanFactory().getBean(resource.Bean);
		/* Gather the arguments needed to call the method. */
		var args = gatherRequestArguments( argumentCollection = arguments, ResourceMatch = resource);
		/* Now call the method on the bean! */
		var methodResult = Invoke(bean, resource.Method, args);
		result.Output = SerializeJSON(methodResult);
		return result;
	}

}