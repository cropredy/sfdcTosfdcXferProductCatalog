public with sharing class HttpRest {

	//	Class to handle HTTP Rest calls to other SFDC instances
	//
	//	[HTTP-00]	- Reached limit on callouts
	//	[HTTP-01]	- Unable to get OAuth 2.0 token from remote SFDC


	String	accessToken;					// OAuth 2.0 access token
	String	sfdcInstanceUrl;				// Endpoint URL for SFDC instance
						
	private HttpResponse send(String uri,String httpMethod) {
		
		return send(uri,httpMethod,null,false);
	}
		
	private HttpResponse send(String uri, String httpMethod, String body, Boolean isJson) {
		
		if (Limits.getCallouts() == Limits.getLimitCallouts())
			throw new CustomException('[HTTP-00] Callout limit: ' + Limits.getCallouts() + ' reached. No more callouts permitted.');
		Http		h		= new Http();
		HttpRequest	hRqst	= new HttpRequest();
		hRqst.setEndpoint(uri);						// caller provides, this will be a REST resource
		hRqst.setMethod(httpMethod);				// caller provides
		hRqst.setTimeout(12000);	
		if (body != null) 
			hRqst.setBody(body);					// caller provides
		if (this.accessToken != null)				// REST requires using the token, once obtained for each request
			hRqst.setHeader('Authorization','Bearer ' + this.accessToken);
		if (isJson)
			hRqst.setHeader('Content-Type', 'application/json');	
		System.debug(LoggingLevel.INFO,	'Before HTTP callout' +
										'\n Http props: ' + h.toString() +
										'\n Endpoint: ' + hRqst.getEndpoint() + 
										'\n Method  : ' + hRqst.getmethod() +
										'\n Body    : ' + hRqst.getBody() +
										'\n Header  : ' + hRqst.getHeader('Authorization'));		
		return h.send(hRqst);					// make the callout
	}
	


	
	
	//	----------------------------------------------------------------------
    //	authenticateByUserNamePassword		: Returns a map of <String,String> of the OAuth 2.0 access token; required before REST calls on SFDC instances can be made 
    //	----------------------------------------------------------------------
    public void authenticateByUserNamePassword(String consumerKey, String consumerSecret, String uName, String uPassword, Boolean isSandbox) {
    	// Reference documentation can be found in the REST API Guide, section: 'Understanding the Username-Password OAuth Authentication Flow'
    	// OAuth 2.0 token is obtained from endpoints:
    	//	PROD orgs	: https://login.salesforce.com/services/oauth2/token
    	//	SANDBOX orgs: https://test.salesforce.com/services/oauth2/token
    	
 		//	OAuth 2.0 access token contains these name/values:
 		//		access_token		: used in subsequent REST calls
 		//		instance_url		: to form the REST URI
 		//		id					: identifies end user
 		//		issued_at			: When signature was created
 		//		signature			: HMAC-SHA256 signature signed with private key - can be used to verify the instance_url	 

		String uri 			= 'https://' + (isSandbox ? 'test' : 'login') + '.salesforce.com/services/oauth2/token';
		String clientId 	= EncodingUtil.urlEncode(consumerKey,'UTF-8');
		String clientSecret = EncodingUtil.urlEncode(consumerSecret,'UTF-8');
		String username		= EncodingUtil.urlEncode(uName,'UTF-8');
		String password		= EncodingUtil.urlEncode(uPassword,'UTF-8');

		String body =	'grant_type=password&client_id=' + clientId + 
						'&client_secret=' + clientSecret +
						'&username=' + username + 
						'&password=' + password; 

		HttpResponse hRes = this.send(uri,'POST',body,false);
		if (hRes.getStatusCode() != 200) 
			throw new CustomException('[HTTP-01] OAuth 2.0 access token request error. Verify username, password, consumer key, consumer secret, isSandbox?  StatusCode=' +
												 hRes.getStatusCode() + ' statusMsg=' + hRes.getStatus());
			
		
		System.debug(LoggingLevel.INFO,'response body =\n' + hRes.getBody());
		

		Map<String,String> res = (Map<String,String>) JSON.deserialize(hRes.getBody(),Map<String,String>.class);

		this.accessToken		= res.get('access_token');		// remember these for subsequent calls
		this.sfdcInstanceUrl 	= res.get('instance_url');
		
		
    }

	//	----------------------------------------------------------------------
	//	doCatalogXfer			: Executes a REST POST on a custom REST Service
	//	----------------------------------------------------------------------
	public CatalogXferRequestResponse.Response doCatalogXfer(CatalogXferRequestResponse.Request rqst) {
		CatalogXferRequestResponse.Response resp	= new CatalogXferRequestResponse.Response();
		
		
		
		HttpResponse hRes 	= this.send(this.sfdcInstanceUrl+'/services/apexrest/catalogImport/v1','POST','{"rqst": ' + JSON.serialize(rqst) + ' }', true);
		System.debug(LoggingLevel.INFO,'status/msg= ' + hRes.getStatusCode() + ' ' + hRes.getStatus() + ' hRes.body = ' + hRes.getBody());
		if (hRes.getBody() == null) {
			resp.statusCode	= hRes.getStatusCode();
			resp.statusMsg	= hres.getStatus();
		}
		else
		if (!hRes.getBody().contains('"cxr":')) {
			resp.statusCode	= hRes.getStatusCode();
			resp.statusMsg	= hres.getStatus() + ' ' + hRes.getBody();
		}
		else
			resp 			= (CatalogXferRequestResponse.Response) JSON.deserialize(hRes.getBody(),CatalogXferRequestResponse.Response.class);
		return resp;	
	}



 
 
 	//	--------------------------------------------------------------
    // 	TEST METHODS - MOCKS
    //	---------------------------------------------------------------	
	public class authenticateByUserNamePasswordMock implements HttpCalloutMock {
    	
    	Boolean	isMockResponseSuccessful;
    	
    	public authenticateByUserNamePasswordMock(Boolean isMockResponseSuccessful) {
    		this.isMockResponseSuccessful	= isMockResponseSuccessful;
    	}
    	
    	public HttpResponse respond(HttpRequest rqst) {
    		HttpResponse hResp		= new HttpResponse();
    		if (this.isMockResponseSuccessful) {
    			hResp.setStatusCode(200);
    			hResp.setBody('{' +			// data copied from SFDC example
    							' "id":"https://login.salesforce.com/id/00Dx0000000BV7z/005x00000012Q9P", ' +
								' "issued_at":"1278448832702",' +
								' "instance_url": "https://na1.salesforce.com",' +
								' "signature":"0CmxinZir53Yex7nE0TD+zMpvIWYGb/bdJh6XfOH6EQ=",' +
								' "access_token": "00Dx0000000BV7z!AR8AQAxo9UfVkh8AlV0Gomt9Czx9LjHnSSpwBMmbRcgKFmxOtvxjTrKW19ye6PE3Ds1eQz3z8jr3W7_VbWmEu4Q8TVGSTHxs"' 
							+'}');			
    		}
    		else {
    			hResp.setStatusCode(400);
    			hResp.setStatus('Bad request');
    		}
    		return hResp;
    	}
    }
    

    
    
   	//	--------------------------------------------------------------
    // 	TEST METHODS - tests
    //	--------------------------------------------------------------- 
	@isTest
    private static void testAuthenticateByUserNamePassword() {
    	HttpRest hr = new HttpRest();
    	try {
    		Test.setMock(HttpCalloutMock.class, new authenticateByUserNamePasswordMock(true));	
    		hr.authenticateByUserNamePassword('somekey','somesecret','someusername@somedomain','somepw+token',false);
    		System.assertEquals('00Dx0000000BV7z!AR8AQAxo9UfVkh8AlV0Gomt9Czx9LjHnSSpwBMmbRcgKFmxOtvxjTrKW19ye6PE3Ds1eQz3z8jr3W7_VbWmEu4Q8TVGSTHxs',hr.accessToken);
    		System.assertEquals('https://na1.salesforce.com',hr.sfdcInstanceUrl);
    	}
    	catch (Exception e) {System.assert(false,'shouldnt. Exception:' + e.getMessage() + e.getStackTraceString());}
    	try {
    		Test.setMock(HttpCalloutMock.class, new authenticateByUserNamePasswordMock(false));
    		hr.authenticateByUserNamePassword('somekey','somesecret','someusername@somedomain','somepw+token',false);
    		System.assert(false,'shouldnt happen, mock should produce error');
    	}
    	catch (Exception e) {System.assert(e.getMessage().contains('[HTTP-01]'),e.getMessage());}
    }



}