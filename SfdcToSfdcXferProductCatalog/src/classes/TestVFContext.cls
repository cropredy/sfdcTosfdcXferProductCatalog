public without sharing class TestVFContext {
	
	//	Test Utility class for simplifying VF testMethods as each test context has to be set up reliably and consistently
	//	getId					: get Id from resPg
	//	getMostRecentMsg		: get most recent Apexpages.Message - use only when a Message is expected (or we are showing the message when no message is expected)
	//	getUrl					: get URL  (or 'null') - handy for Asserts
	//	init					: initialize for each user interaction
	
	
	public	ApexPages.StandardController				ctlr;
	public	ApexPages.StandardSetController				ssCtlr;
	
	public	PageReference								resPg;
	
	//	-------------------------------------------------
	//				CONSTRUCTOR
	//	-------------------------------------------------
	public TestVFContext() {}
	
	
	//	------------------------------------------------
	//	getId		: get Id from resPg
	//	------------------------------------------------
	public ID	getId() {return resPg != null ? resPg.getUrl().substring(1,16) : null;}
	
	//	------------------------------------------------
	//	getMostRecentMsg		: get most recent Apexpages.Message - use only when a Message is expected (or we are showing the message when no message is expected)
	//	------------------------------------------------
	public String getMostRecentMsg() {
		return ApexPages.hasMessages() 
			? ApexPages.getMessages()[ApexPages.getMessages().size()-1].getSummary() + ' ' + ApexPages.getMessages()[ApexPages.getMessages().size()-1].getDetail() 
			: null;
	}

	public Integer getMsgCount() {
		return ApexPages.hasMessages() ? ApexPages.getMessages().size() : 0;
	}
	
	
	//	------------------------------------------------
	//	getUrl		: get URL  (or 'null') - handy for Asserts
	//	------------------------------------------------
	public String getUrl() {return resPg != null ? resPg.getUrl() : 'null';}
	
	//	-------------------------------------------------
	//	init		: initialize for each user interaction
	//	-------------------------------------------------
	//		sObj 			= either a new sObj() or an existing sobject in database
	//		pg				= VF page being tested
	//		queryStringMap	= Map key | value for queryString parms	
	public void init(SObject sObj,  PageReference pg, Map<String,String> queryStringParmMap) {
		this.ctlr			= sObj == null ? null : new ApexPages.StandardController(sObj);				// Initialize the controller
		if (pg != null) {
			Test.setCurrentPageReference(pg);											// Set the current page
			if (queryStringParmMap != null)
				for (String k: queryStringParmMap.keySet())										// Put parameters on current page
					pg.getParameters().put(k,queryStringParmMap.get(k));
		}
	}
	
	@isTest
	private static void testVFContext() {
		TestVFContext tvfc		= new TestVFContext();
		PageReference	pg		= new PageReference('na1.salesforce.com/123456789ABCDEF');
		tvfc.init(new Account(),pg,null);
		tvfc.init(null,pg,new Map<String,String> {'00parm' => '00parmVal'});
		
		ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.INFO,'[XX-00] summary error','detail error'));
		System.assertEquals(1,		tvfc.getMsgCount());
		System.assert(tvfc.getMostRecentMsg().contains('[XX-00]'));
		
		tvfc.resPg				= new PageReference('na1.salesforce.com/'+UserInfo.getUserId() );
		System.assertEquals('na1.salesforce.com/'+UserInfo.getUserId(),		tvfc.getUrl());
		
		tvfc.resPg				= new PageReference('/' + UserInfo.getUserId());
		System.assert(UserInfo.getUserId().contains(tvfc.getId()));
		
		
	}
}