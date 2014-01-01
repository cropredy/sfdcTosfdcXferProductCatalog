@isTest
private without sharing class Test_ProductAdminActionCustomController {

	//	Tests
	//	testProductCatalogXfer		: Needs access to std pricebook


	//	Mock Callout classes
	public class MockAuthenticateResponseGenerator implements HttpCalloutMock {
		private Boolean	enableMockSuccess;
		
		public HTTPResponse respond(HTTPRequest req) {
	    // Create a fake response
        	HttpResponse res = new HttpResponse();
        	res.setBody('{"access_token":"fooAccessToken","instance_url" : "https://foo.com"}');
        	res.setStatusCode(this.enableMockSuccess ? 200 : 400);
        	return res;
    	}
    	public MockAuthenticateResponseGenerator(Boolean enableMockSuccess) {
    		this.enableMockSuccess			= enableMockSuccess;
    	}
    	
    	
	}
	
	public class MockXferCatalogResponseGenerator implements HttpCalloutMock {
		private Boolean	enableMockSuccess;
		
		public HTTPResponse respond(HTTPRequest req) {
	    // Create a fake response
        	HttpResponse res = new HttpResponse();
        	res.setBody('{"cxr":"CatalogXferResponse","statusCode" : ' + (this.enableMockSuccess ?  '"200" ' : '"400" ') + ', "statusMsg" : null, "log" : "log"}');
        	res.setStatusCode(this.enableMockSuccess ? 200 : 400);
        	return res;
    	}
    	public MockXferCatalogResponseGenerator(Boolean enableMockSuccess) {
    		this.enableMockSuccess			= enableMockSuccess;
    	}
	}



	//	------------------------------------------------
	//	testProductCatalogXfer		: Needs access to std pricebook, hence seeAllData=true
	//	------------------------------------------------
	@isTest(SeeAllData=true)
	private static void testProductCatalogXfer() {
		
		//	Two pricebooks, both with USD and AUD prices
		//	pbList[0] - product 00_00, 00_01
		//	pbList[1] - product 01_100, 01_101
		
		List<Pricebook2>	pbList 	= new List<Pricebook2> {	new Pricebook2 (name = '00Pricebook'),
																new Pricebook2 (name = '01Pricebook')
															};
		insert pbList;													
		List<Product2>		pList	= new List<Product2> {	new Product2 (name='00_00Product', productCode='00ProductSku', isActive=true),		// add any required fields here
															new Product2 (name='00_01Product', productCode='01ProductSku', isActive=true),	
															new Product2 (name='01_100Product', productCode='100ProductSku', isActive=true),
															new Product2 (name='01_101Product', productCode='101ProductSku', isActive=true)	
															};
		
		insert pList;
		
		ID stdPbId					= Util.getStdPriceBook().id;
		//	insert stdPB PBE
		List<PricebookEntry>	pbeList	= new List<PricebookEntry> {	new PricebookEntry(pricebook2Id = stdPbId, currencyIsoCode='AUD', isActive = true, product2Id = pList[0].id, unitPrice = 11.00),
																		new PricebookEntry(pricebook2Id = stdPbId, currencyIsoCode='AUD', isActive = true, product2Id = pList[1].id, unitPrice = 11.00),
																		new PricebookEntry(pricebook2Id = stdPbId, currencyIsoCode='AUD', isActive = true, product2Id = pList[2].id, unitPrice = 11.00),
																		new PricebookEntry(pricebook2Id = stdPbId, currencyIsoCode='AUD', isActive = true, product2Id = pList[3].id, unitPrice = 11.00),
																		new PricebookEntry(pricebook2Id = stdPbId, currencyIsoCode='USD', isActive = true, product2Id = pList[0].id, unitPrice = 10.00),
																		new PricebookEntry(pricebook2Id = stdPbId, currencyIsoCode='USD', isActive = true, product2Id = pList[1].id, unitPrice = 10.00),
																		new PricebookEntry(pricebook2Id = stdPbId, currencyIsoCode='USD', isActive = true, product2Id = pList[2].id, unitPrice = 10.00),
																		new PricebookEntry(pricebook2Id = stdPbId, currencyIsoCode='USD', isActive = true, product2Id = pList[3].id, unitPrice = 10.00)
		};
		insert pbeList;
		
		// insert custom pb PBE																
		pbeList	= new List<PricebookEntry> {							new PricebookEntry(pricebook2Id = pbList[0].id, currencyIsoCode='AUD', isActive = true, product2Id = pList[0].id, unitPrice = 11.00),
																		new PricebookEntry(pricebook2Id = pbList[0].id, currencyIsoCode='AUD', isActive = true, product2Id = pList[1].id, unitPrice = 11.00),
																		new PricebookEntry(pricebook2Id = pbList[0].id, currencyIsoCode='USD', isActive = true, product2Id = pList[0].id, unitPrice = 10.00),
																		new PricebookEntry(pricebook2Id = pbList[0].id, currencyIsoCode='USD', isActive = true, product2Id = pList[1].id, unitPrice = 10.00),
																		
																		new PricebookEntry(pricebook2Id = pbList[1].id, currencyIsoCode='AUD', isActive = true, product2Id = pList[2].id, unitPrice = 11.00),
																		new PricebookEntry(pricebook2Id = pbList[1].id, currencyIsoCode='AUD', isActive = true, product2Id = pList[3].id, unitPrice = 11.00),
																		new PricebookEntry(pricebook2Id = pbList[1].id, currencyIsoCode='USD', isActive = true, product2Id = pList[2].id, unitPrice = 10.00),
																		new PricebookEntry(pricebook2Id = pbList[1].id, currencyIsoCode='USD', isActive = true, product2Id = pList[3].id, unitPrice = 10.00)
																};
		insert pbeList;														
																
		//	setup test Connected_App__c
		List<Connected_App__c>	caList		= new List<Connected_App__c> {	new Connected_App__c(name = 'sandbox00', consumer_key__c = '00foo', consumer_secret__c = '00bar'),
																			new Connected_App__c(name = 'sandbox01', consumer_key__c = '01foo', consumer_secret__c = '01bar')
																			};
		insert caList;																																																			
		
		
		TestVFContext tvfc			= new TestVFContext();
		tvfc.init(null,Page.Product_AdminActions,null);
		
		ProductAdminCustomController ctlr	= new ProductAdminCustomController();
		
		//	0.1  Test Authentication
		
		System.assertEquals(false,				ctlr.auth.isAuthenticated);			// haven't authenticated yet.
		System.assert(ctlr.auth.connectedOrgs.size() > 0);							// reads from Connected_App__c the available connected orgs; make sure they are set up above
		
		ctlr.auth.orgname				= caList[0].name;							// simulate user selection
		ctlr.auth.username				= 'foo@foo.com';							// values are irrelevant as Mock provides a success response for us
		ctlr.auth.pwToken				= 'password+token';
		ctlr.auth.isSandbox				= true;
		
		Test.startTest();
		Test.setMock(HttpCalloutMock.class, new MockAuthenticateResponseGenerator(false));
		tvfc.resPg			= ctlr.authenticateToRemoteOrg();						// authenticate (using Mock w/ error)
		System.assert(tvfc.getMostRecentMsg().contains('[PACC-00]'),tvfc.getMostRecentMsg());	// verify error
		System.assertEquals(true,		ctlr.getShowPageMessageDetail());
		System.assertEquals(false,		ctlr.auth.isAuthenticated);					// verify
		
		Test.setMock(HttpCalloutMock.class, new MockAuthenticateResponseGenerator(true));
		tvfc.resPg			= ctlr.authenticateToRemoteOrg();						// authenticate (using Mock w/ success)
		
		System.assertEquals(true,		ctlr.auth.isAuthenticated);					// verify
		
		//	0.2 Test getters and setters at initial page state
				
		System.assertEquals(0,			ctlr.xfer.getSelectedProductList().size());		// no user action yet
		System.assertEquals(0,			ctlr.xfer.getSelectedCurrencyList().size());		// " "
		System.assertNotEquals(0,		ctlr.xfer.xferScopeOptions.size());
		System.assertEquals(null,		ctlr.xfer.getSelectedPricebookName());
		System.assertEquals(false,		ctlr.xfer.isPricebookSelectionEnabled);
		System.assertEquals(false,		ctlr.xfer.isProductSelectionEnabled);
		System.assertEquals(null,		ctlr.xfer.isXferEnabledtoSmashDuplicates);
		System.assertEquals(null,		ctlr.xfer.isXferDebugEnabled);
		System.assertEquals(null,		ctlr.xfer.selectedPriceBookId);
		System.assert(ctlr.xfer.xferrableCurrencyList.size() > 0);
		
		//	0.3	Choose to xfer PricebookEntries for both AUD and USD
		ctlr.xfer.xferScope 				= 'Products+PricebookEntries';
		
		//	0.31 Try and transfer without picking a currency
		tvfc.resPg						= ctlr.xferCatalog();
		System.assert(tvfc.getMostRecentMsg().contains('[PACC-01]'),tvfc.getMostRecentMsg());	// verify error
		
		
		ctlr.xfer.setSelectedCurrencyList(new List<String> {'AUD','USD'});
			
		System.assertEquals(0,			ctlr.xfer.getSelectedProductList().size());
		System.assertEquals(2,			ctlr.xfer.getSelectedCurrencyList().size());		// AUD + USD
		System.assertEquals(null,		ctlr.xfer.getSelectedPricebookName());
		System.assertEquals(true,		ctlr.xfer.isPricebookSelectionEnabled);
		System.assertEquals(false,		ctlr.xfer.isProductSelectionEnabled);
		System.assertEquals(null,		ctlr.xfer.isXferEnabledtoSmashDuplicates);
		System.assertEquals(null,		ctlr.xfer.isXferDebugEnabled);
		System.assertEquals(null,		ctlr.xfer.selectedPriceBookId);
		System.assert(ctlr.xfer.xferrableCurrencyList.size() > 0);
		System.assert(ctlr.xfer.xferrablePricebooks.size() > 0);
		
		
		//	0.4 Select one of the new pricebooks	
		ctlr.xfer.selectedPricebookId	= pbList[0].id;
		tvfc.resPg						= ctlr.xferResetQuery();					// simulate page indicating priebook has been selected
		
		System.assertEquals(true,		ctlr.xfer.isProductSelectionEnabled);
		System.assertequals(2,			ctlr.xfer.xferrableProductList.size());			// two SKUs on selected pricebook
		System.assertEquals(0,			ctlr.xfer.getSelectedProductList().size());
		
		//	0.41 Try and transfer without making any SKU selections
		tvfc.resPg						= ctlr.xferCatalog();
		System.assert(tvfc.getMostRecentMsg().contains('[PACC-02]'),tvfc.getMostRecentMsg());	// verify error
				
		//	0.5 Select both SKUs
		ctlr.xfer.xferrableProductList[0].isSelected		= true;
		ctlr.xfer.xferrableProductList[1].isSelected		= true;
		
		//	0.6 xfer the catalog using another mock interface
		Test.setMock(HttpCalloutMock.class, new MockXferCatalogResponseGenerator(false));
		tvfc.resPg						= ctlr.xferCatalog();						// simulate page indicating pricebook has been selected
		System.assert(ctlr.xfer.getLog().contains('[PACC-05]'),ctlr.xfer.getLog());	// verify failure
		
		
		Test.setMock(HttpCalloutMock.class, new MockXferCatalogResponseGenerator(true));
		tvfc.resPg						= ctlr.xferCatalog();									// simulate page indicating pricebook has been selected
		System.assert(tvfc.getMostRecentMsg().contains('[PACC-06]'),tvfc.getMostRecentMsg());	// verify success
		System.assert(ctlr.xfer.getLog().length() > 0);
		
		//	0.7 Transfer reset to reauthenticate
		tvfc.resPg						= ctlr.xferReset();
		System.assertEquals(false,		ctlr.auth.isAuthenticated);
		System.assertEquals(false,		ctlr.xfer.isPricebookSelectionEnabled);
		System.assertEquals(false,		ctlr.xfer.isProductSelectionEnabled);
		
		
		Test.stopTest();
		
	}

}