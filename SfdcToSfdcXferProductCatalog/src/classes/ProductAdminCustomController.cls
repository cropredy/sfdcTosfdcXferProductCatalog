public without sharing class ProductAdminCustomController extends ControllerBase {


	// ----------------------------------------------------------------------------
	// ProductAdminCustomController - Provides admin functions for maanipulating the Product Catalog
	//
	//		
	//	Supports these specific use cases: 
	//		Authenticate to remote SFDC org
	//		Transfer some or all of a product2-pricebookEntry-pricebook2	
	//
	
	//	Errors
	//	[PACC-00]	:	OAuth 2.0 authentication error to remote SFDC org 
	//	[PACC-01]	: 	Choose at least one SKU before transfer
	//	[PACC-02]	:	Choouse at least 1 currency before PBE transfer
	//	[PACC-03]	: 	Switch pricebook error
	//	[PACC-04]	: 	Transfer reset error
	//	[PACC-05]	:	Transfer error
	//	[PACC-06]	:	Transfer success
	// ----------------------------------------------------------------------------
	
	// --------------------------------------------------------
	// PUBLIC PROPERTIES - EXPOSED TO VF PAGES
	// --------------------------------------------------------
	
	public 	AuthParms						auth				{get; set;}				// Represents authentication input and result	
	public	Xfer							xfer				{get; set;}				// Represents instructions for transfer
	
	
	//	------------------------------------------------------
	//	INNER CLASS - AuthParms
	//	-----------------------------------------------------
	public class AuthParms {
		
		public 	List<SelectOption> 	connectedOrgs {										// Available target orgs
			get {
				this.connectedOrgs		= new List<SelectOption> ();
				for (Connected_App__c ca: [select id, name from Connected_App__c] )
					this.connectedOrgs.add(new SelectOption(ca.name,ca.name));
				return this.connectedOrgs;
			}
			private set;
		}
			
		private HttpRest			hr;
		public	Boolean				isAuthenticated		{get {return this.isAuthenticated == null ? false: this.isAuthenticated;} private set;}
		public 	Boolean				isSandbox			{get; set;}	
		public 	String				orgname				{get; set;}
		public 	transient String	pwToken				{get; set;}
		public 	String				username			{get; set;}
		
	}
	
	//	------------------------------------------------------
	//	INNER CLASS - Xfer : Transfer details 
	//	------------------------------------------------------
	public class Xfer {
		
		private List<String> xFerActionLabelList						= new List<String> {'Products' ,
																							'Products+PricebookEntries',
																							'PricebookEntries'};	
		private ProductAdminCustomController ctlr;				// gives inner class obj access to outer class methods
		
		
		//	-----------CONSTRUCTOR -------------	
		public Xfer(ProductAdminCustomController	 ctlr) {
			this.ctlr			= ctlr;
		}


		//	-----------------------------------------------------------
		//	getHasAnySkuSelected : user selected a SKU? on VF page
		//	-----------------------------------------------------------
		private Boolean 			getHasAnySkuSelected() {			 
			Boolean 		res = false;
			for (XferrableProduct xferP : this.xferrableProductList)
				if (xferP.isSelected) {res = true; break;}
			return res;
		}
		//	-----------------------------------------------------------
		//	getLog : diagnostic log of actions displayed on VF page; as HTML
		//	-----------------------------------------------------------
		public String				getLog() {
			return this.log != null ? this.log.replaceAll('\n','<br/>') : null;
		}
		
		//	-----------------------------------------------------------
		//	getSelectedCurrencyList : Currencies that user selected on VF page
		//	-----------------------------------------------------------
		public List<String>			getSelectedCurrencyList() {return this.selectedCurrencyList;}
		
		//	-----------------------------------------------------------
		//	getSelectedPricebookName : Name of pricebook selected by user on VF page to xfer to target org
		//	-----------------------------------------------------------
		public String 				getSelectedPricebookName() {
			String res;
			for (SelectOption so : this.xferrablePricebooks)
				if (so.getValue() == this.selectedPriceBookId) {res = so.getLabel(); break;}
			return res;
		}
		
		//	-----------------------------------------------------------
		//	getSelectedPIdSet : Selected Products as a set of IDs to fetch using dyn SOQL for xfer
		//	-----------------------------------------------------------
		private Set<ID>				getSelectedPIdSet() {
			Set<ID> res			= new Set<ID>();
			for (Product2 p : this.getSelectedProductList())
				res.add(p.id);
			return res;	
		}

		//	-----------------------------------------------------------
		//	getSelectedProductList : Selected Products from Wrapper class of available SKus with check boxes; important fields only
		//	-----------------------------------------------------------
		public List<Product2>		getSelectedProductList() {
			List<Product2>			res = new List<Product2> ();
			for (XferrableProduct xp : this.xferrableProductList)
				if (xp.isSelected)
					res.add(xp.p);
			return res;		
		}
		
		//	-----------------------------------------------------------
		//	getSourcePricebookEntries : PricebookEntries for selected SKUs in selected currencies on both std pricebook and selected pricebook
		//	-----------------------------------------------------------
		private List<PricebookEntry> getSourcePricebookEntries() {
			return [select id, currencyIsoCode, isActive, pricebook2Id, product2Id, productCode, unitPrice, useStandardPrice from PricebookEntry
					where 	(pricebook2Id = : this.selectedPricebookId or
							pricebook2Id = : [select id from Pricebook2 where isStandard = true limit 1].id) and
							currencyIsoCode IN : this.selectedCurrencyList and
							product2Id IN : this.getSelectedProductList()];
		}
		
		
		public Boolean				isPricebookSelectionEnabled {
			get {return xferScope != null && xferScope != 'Products' ? true : false;}
			private set;
		}
		
		public Boolean				isProductSelectionEnabled {
			get {return (xferScope != null && xferScope == 'Products') || this.selectedPriceBookId != null ? true : false; }
			private set;
		}
		public Boolean				isXferEnabledtoSmashDuplicates	{get; set;}				// instruction for handling dups in target org
		public Boolean				isXferDebugEnabled				{get; set;}				// instruction to turn on additional debugging in target org
		
		private String				log;													// diagnostics to display on admin VF page
		
		private void logAdd(String entry) {
			this.log = this.log == null ? entry : this.log + '\n' + entry;
		}
		
		private String[]			selectedCurrencyList	= new List<String> ();			// which currencies of PBE to xfer
		public String				selectedPriceBookId {get; set;}							// pricebook used as source for locating products and PBE
				
		public void					setSelectedCurrencyList (String[] selectedCurrencies) {	 
			this.selectedCurrencyList	= selectedCurrencies;
		}
		
		
		//	-----------------------------------------------------------
		//	transfer : the worker, does REST call on custom REST service in target org
		//	-----------------------------------------------------------
		private void transfer() {
			this.log	= null;
			CatalogXferRequestResponse.Request	rqst	= new CatalogXferRequestResponse.Request();
			rqst.instr									= new CatalogXferRequestResponse.Instructions();
			rqst.instr.smash							= this.isXferEnabledtoSmashDuplicates;
			rqst.instr.doXferPricebookEntries			= this.xferScope == 'Products+PricebookEntries' || this.xferScope == 'PricebookEntries';
			rqst.instr.doXferProducts					= this.xferScope == 'Products+PricebookEntries' || this.xferScope == 'Products';
			rqst.instr.stdPbId							= Util.getStdPriceBook().id;
			
			//	Build the payload of source org SObjects; use dynamic SOQL to fetch all fields so they can be inserted in target org.
			rqst.pb								= Database.query('Select id, name from Pricebook2 where id =:selectedPriceBookId'); // Note simple bind variable inside of string
			rqst.pList							= Database.query('Select ' + Util.getAllSObjFieldNamesAsString('Product2') + 
																	' from Product2 where id IN (' + 
																			Util.flattenSearchIdSet(this.getSelectedPIdSet(),',') +
																		 ' )' );  
			rqst.pbeList						= this.getSourcePricebookEntries();
			
			CatalogXferRequestResponse.Response	resp 	= ctlr.auth.hr.doCatalogXfer(rqst);
			this.logAdd(resp.log);
			if (resp.statusCode != 200)
				this.logAdd('[PACC-05] ERROR in target system: ' + resp.statusMsg); 
			
		}		
		//	-----------------------------------------------------------
		//	xferrableCurrencyList : all available currencies in source org
		//	-----------------------------------------------------------
		public 	List<SelectOption> 	xferrableCurrencyList {									// PBE currencies to transfer
			get {
				this.xferrableCurrencyList		= new List<SelectOption> ();
				for (AggregateResult aggRes: [select currencyisoCode from PricebookEntry group by CurrencyIsoCode])
					this.xferrableCurrencyList.add(new SelectOption((String)aggRes.get('CurrencyIsoCode'),(String)aggRes.get('CurrencyIsoCode')));
				return this.xferrableCurrencyList;
			}
			private set;
		}
		//	-----------------------------------------------------------
		//	xferrablePricebooks : all available custom pricebooks in source org
		//	-----------------------------------------------------------
		public 	List<SelectOption> 	xferrablePricebooks {									// Pricebooks that can be copied
			get {
				if (this.xferrablePricebooks == null) {
					this.xferrablePricebooks		= new List<SelectOption> ();
					for (Pricebook2 pb : [select id, name 
												from Pricebook2 where isActive = true and isStandard = false order by name asc]) 
						this.xferrablePricebooks.add(new SelectOption((String) pb.id,pb.name));
				}			
				return this.xferrablePricebooks;
			}
			private set;
		}
		//	-----------------------------------------------------------
		//	xferrableProductList : Products that belong to the selected pricebook; if selected; otherwise all available active Products in source org
		//	-----------------------------------------------------------
		public List<XferrableProduct>	xferrableProductList {
			get {
				if (this.xferrableProductList == null) {
					this.xferrableProductList	= new List<XferrableProduct> ();
					if (this.selectedPricebookId != null)							// Get all products for given Pricebook where PBE exits in one of the selected currencies
						for (Product2 p : [select id, productCode, name, 
												(select id, currencyIsoCode, unitPrice 
													from PricebookEntries
												)
											from Product2
												where id IN  (select product2Id 
																	from PricebookEntry
																	where 	pricebook2Id = :this.selectedPricebookId and
																			isActive = true and
																			currencyIsoCode IN :new Set<String> (this.selectedCurrencyList)) 
												order by productCode asc				
											])
							this.xferrableProductList.add(new XferrableProduct(p));				

					else															// Get all products (active)
						for (Product2 p: [select id, productCode, name from Product2 
											where isActive = true
											order by productCode])
							this.xferrableProductList.add(new XferrableProduct(p));	
				}						
				return this.xferrableProductList;								
				
			}
			private set;
		}
		//	-----------------------------------------------------------
		//	xferScopeOptions : Options for the transfer (scope of sobjects to xfer)
		//	-----------------------------------------------------------
		public String xferScope							{get; set;}				// Scope of xfer
		public List<SelectOption>	xferScopeOptions {
			get {
				List<SelectOption> res 	= new List<SelectOption>();
				for (String option : this.xFerActionLabelList)
					res.add(new SelectOption(option,option));
				return res;
			}
			private set;									
		}
	}
	
	//	------------------------------------------------------
	//	INNER CLASS XferrableProduct
	//	------------------------------------------------------
	public class XferrableProduct{
		public Boolean				isSelected			{get; set;}
		public Product2				p					{get; private set;}
		
		public XferrableProduct(Product2 p) {			// Constructor
			this.isSelected = false;
			this.p			= p;
		}
	}
	
	
	// --------------------------------------------------------
	// PRIVATE PROPERTIES - HIDDEN FROM VF PAGES 
	// -------------------------------------------------------- 

	// --------------------------------------------------------
	// 							CONSTRUCTOR
	// --------------------------------------------------------
	public ProductAdminCustomController() {
		try {
			super();
			this.auth				= new AuthParms();				// for admin action: Authenticate
			this.xfer				= new Xfer(this);				// for admin action: XferCatalog
		}
		catch (Exception e) {
			Util.addVFPageMessage(Apexpages.Severity.ERROR,'ProductAdminCustomController.constructor',e);
			this.hasConstructorError = true;
		}
	} 
	//	-------------------- END CONSTRUCTOR -------------------------
	
	
	//	-------------------------------------------------------------------------------------
	//							ACTION METHODS
	//	-------------------------------------------------------------------------------------
	
	// ---------------------------------------------------------------------------------------
	//	ACTION METHOD - authenticateToRemoteOrg
	//	--------------------------------------------------------------------------------------
	public PageReference	authenticateToRemoteOrg() {
 		PageReference 			resPg;
 		
 		try { 			
 			
 			Connected_App__c ca			= [select id, consumer_key__c, consumer_secret__c from Connected_App__c where name = :this.auth.orgName];
 			HttpRest hr					= new HttpRest();
 			hr.authenticateByUserNamePassword(ca.consumer_Key__c, ca.consumer_Secret__c, this.auth.username, this.auth.pwToken, this.auth.isSandbox);
 			this.auth.isAuthenticated	= true;
 			this.auth.hr				= hr;
 			Util.addVFPageMessage(ApexPages.Severity.INFO,'Login successful',null);
 			}
 		
 		catch (Exception e) {
 			this.auth.isAuthenticated	= false;
 			Util.addVFPageMessage(ApexPages.Severity.ERROR,'[PACC-00] Authentication error',e);			
 			resPg						= null;															// error, display to user
 		}
 		
 		return resPg;
 	}

	// ----------------------------------------------------------------------------------------
	// ACTION METHOD	- xferCatalog		: Copies Product2, PBE, Pricebook2, and related configuration records to target SFDC org 
	// ----------------------------------------------------------------------------------------
 	public PageReference	xferCatalog() {
 		PageReference 			resPg;
 		
 		try {
 			//	Do input validations
 			if ((this.xfer.xferScope == 'Products+PricebookEntries' || this.xfer.xferScope == 'PricebookEntries') && this.xfer.selectedCurrencyList.size() == 0)
 				Util.addVFPageMessage(ApexPages.Severity.ERROR,'[PACC-01] Please choose at least one currency for the pricebook entry transfer.',null);
 			else
			if (!this.xfer.getHasAnySkuSelected())
 				Util.addVFPageMessage(ApexPages.Severity.ERROR,'[PACC-02] Please choose at least one SKU for the transfer.',null);	
 			else { 
 				xfer.transfer();
 				Util.addVFPageMessage(ApexPages.Severity.INFO,'[PACC-06] Transfer complete, see log for details. Callouts to date: ' + Limits.getCallouts() + ' vs Limit: ' + Limits.getLimitCallouts() ,null);
 			}	
 		}
 		
 		catch (Exception e) {
 			Util.addVFPageMessage(ApexPages.Severity.ERROR,'[PACC-05] ',e);			
 			resPg						= null;															// error, display to user
 		}
 		
 		return resPg;
 	}
	//	--------------------------------------------------------------------------------------
	//	ACTION METHOD - xferReset : To do another transfer, force reauthentication
	//	--------------------------------------------------------------------------------------
	public PageReference xferReset() {
		PageReference 			resPg;
 		
 		try {
 			this.auth				= new AuthParms();				// for adminactions
			this.xfer				= new Xfer(this); 
 		}
 		
 		catch (Exception e) {
 			Util.addVFPageMessage(ApexPages.Severity.ERROR,'[PACC-04] ',e);			
 			resPg						= null;															// error, display to user
 		}
 		
 		return resPg;
	}


	// ----------------------------------------------------------------------------------------
	// ACTION METHOD	- xferResetQuery		: Recognizes change in pricebook/pricebook entry currencies from admin actions page.
	// ----------------------------------------------------------------------------------------
 	public PageReference	xferResetQuery() {
 		PageReference 			resPg;
 		
 		try {
 			this.xfer.xferrableProductList = null;		// reset list of selectable/selected SKUs based on new selections	
 		}
 		
 		catch (Exception e) {
 			Util.addVFPageMessage(ApexPages.Severity.ERROR,'[PACC-03] ',e);			
 			resPg						= null;															// error, display to user
 		}
 		
 		return resPg;
 	}



		

}