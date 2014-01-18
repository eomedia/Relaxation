component
	accessors="true"
	hint="I help gather meta data for and generate API docs."
	output="false"
{
	property name="Relaxation" type="component";
	
	/**
	* @hint "I am the constructor."
	**/
	public DocGenerator function init() {
		return this;
	}
	
	/**
	* @hint "I gather all of the documentation meta data for all of the resources."
	**/
	package array function getFullMeta() {
		var config = Relaxation.getConfig();
		var fullMeta = [];
		for ( var resource in config.Resources ) {
			ArrayAppend(fullMeta, getResourceMeta(resource));
		}
		return fullMeta;
	}
	
	/**
	* @hint "Given a function reference, I return the function metadata."
	**/
	package struct function getFunctionMeta( required any _function ) {
		var meta = getMetaData(arguments._function);

		param name="meta.access" default="public";
		param name="meta.hint" default="";
		param name="meta.output" default="true";
		param name="meta.returntype" default="any";
		for ( var arg in meta.parameters ) {
			arg.type = structKeyExists(arg, "type") ? arg.type : 'any';
		}
		return meta;
	}
	
	/**
	* @hint "Given a resource, I gather the meta for that resource."
	**/
	package struct function getResourceMeta( required struct Resource ) {
		var meta = { 
			"Pattern" = reReplace(arguments.Resource.Pattern, "/$", "")
			,"Verbs" = []
		};
		for ( var verb in ListToArray('GET,PUT,POST,DELETE') ) {
			if ( StructKeyExists(arguments.Resource, verb) ) {
				var verbStruct = arguments.Resource[verb];
				var bean = Relaxation.getBeanFactory().getBean(verbStruct.bean);
				var method = bean[verbStruct.method];
				var defaults = StructKeyExists(verbStruct, 'DefaultArguments') ? verbStruct.DefaultArguments : {};
				
				// added apigee meta items
				var apigeeName = StructKeyExists(verbStruct, 'apigeeName') ? verbStruct.apigeeName : '';					
				var apigeeDoc = StructKeyExists(verbStruct, 'apigeeDoc') ? verbStruct.apigeeDoc : '';
				
				var fMeta = {"Verb" = verb, "DefaultArguments" = defaults, "apigeeName" = apigeeName, "apigeeDoc" = apigeeDoc};
				StructAppend(fMeta, getFunctionMeta(method));
				ArrayAppend(meta.Verbs, fMeta);
			}
		}
		return meta;
	}
	
	/**
	* @hint "I will render the API docs."
	* @output true
	**/
	package void function renderDocs() {
		var docMeta = getFullMeta();
		include "./_docpage.cfm";
		abort;
	}
	
}