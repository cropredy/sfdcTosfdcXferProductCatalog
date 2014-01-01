@RestResource(urlMapping='/catalogImport/v1/*')
global without sharing class CatalogImportRestService {

	//	------------------------------------
	//	Caveats
	//	1. Relies on Product Codes being unique across Product2 in a given org.
	//	2. Does not handle (yet) copying source->target Product2 lookup fields (e.g. Bill-of-materials explosions)
	//	3. Testmethods which require seeAllData=true because of reliance on standard pricebook presume that the test data does not exist in given org
	//	4. There is no support for deletion of products or pricebookentries in the target org; only upsert
	//	5. Testmethods that insert test Product2 records have to include any customrequired fields in the org
	//	6. Multicurrency must be enabled and testdata relies on AUD and USD currencies; change if required


	//	-------------------------------------
	//	INNER CLASS : Catalog  Maps and others variables to help in cross referencing source to target operations
	//	-------------------------------------
	public class Catalog {
		
		ID							pbId;
		ID							stdPbId;
																				
		Map<String,PricebookEntry>	stdPbSkuCurrencyToPbeMap	= new Map<String,PricebookEntry> ();			// Standard pricebook, key is productCode+IsoCurrency
		Map<String,PricebookEntry>	customPbSkuCurrencyToPbeMap	= new Map<String,PricebookEntry> ();			// Custom pricebook, key is productCode+IsoCurrency
		Map<String,Product2>		pIdToProductMap				= new Map<String,Product2>();					// key is product2.Id - note use of String as key to assist testmethods
		Map<String,Product2>		skuToProductMap				= new Map<String,Product2>();					// key is productCode
		
		public Catalog(ID stdPbId, ID customPbId) {
			this.stdPbId			= stdPbId;
			this.pbId				= customPbId;
		}
		
		public String debug() {
			String	res	= '';
			res	= 		res + '\npIdToProductMap              =';
			for (Product2 p : pIdToProductMap.values())	res = res + '\n   product: ' + p.Id + ' ' + p.productCode;
			res	= 		res + '\nskuToProductMap              =';
			for (Product2 p : skuToProductMap.values())	res = res + '\n   product: ' + p.Id + ' ' + p.productCode;
			res	= 		res + '\nstdPbSkuCurrencyToPbeMap     =';
			for (PricebookEntry pbe : stdPbSkuCurrencyToPbeMap.values())	res = res + '\n   pbeId: ' + pbe.id + ' pId: ' + pbe.product2Id + ' ' + pbe.unitPrice + ' ' + pbe.currencyisoCode + ' pbId:' + pbe.pricebook2Id;
			res	= 		res + '\ncustomPbSkuCurrencyToPbeMap  =';		
			for (PricebookEntry pbe : customPbSkuCurrencyToPbeMap.values())	res = res + '\n   pbeId: ' + pbe.id + ' pId: ' + pbe.product2Id + ' ' + pbe.unitPrice + ' ' + pbe.currencyisoCode + ' pbId:' + pbe.pricebook2Id;
			return res;
		}
		
		
	}
	
	@HttpPost
	global static CatalogXferRequestResponse.Response doPost(CatalogXferRequestResponse.Request rqst) {
		CatalogXferRequestResponse.Response	resp		= new CatalogXferRequestResponse.Response();
		System.RestRequest					restRqst	= System.RestContext.request;
		System.RestResponse 				restResp	= System.RestContext.response;
		Savepoint							sp;
		resp.addLogMsg('CatalogImportRestService POST entered with instructions: ' + rqst.instr);		
		Catalog								srcCat	= new Catalog(rqst.instr.stdPbId, rqst.pb != null ? rqst.pb.id : null);
		Catalog								tgtCat	= new Catalog([select id from pricebook2 where isStandard = true].id,null);
		
		sp												= Database.setSavePoint();
		
		try {
			if (rqst.instr.doXferProducts) {
				srcCat.pIdToProductMap			= getSourceProductsByPId(rqst,resp,'[XferProducts 1.1] Locate products in source org corresponding to source product List');
				tgtCat.skuToProductMap			= getTargetProductsBySku(rqst,resp,'[XferProducts 1.2] Locate products in target org corresponding to source product List...');
				if (rqst.instr.isDebugEnabled)
					debug(resp,srcCat,tgtCat);
				tgtCat.skuToProductMap			= upsertSourceProductsToTarget(rqst,resp,srcCat,tgtCat,'[XferProducts 1.3] Upsert source products to target products...');
			}
			if (rqst.instr.doXferPricebookEntries) {
				tgtCat.pbId 	= getTargetPricebook(rqst,resp,'[XferPbe 1.1] Locate pricebook ' + rqst.pb.name + ' in target org');
				if (tgtCat.pbId == null) 
					tgtCat.pbId = createTargetPricebook(rqst,resp,'[XferPbe 1.1.1] Create pricebook in target org ...');
					
				if (srcCat.pIdToProductMap.size() == 0)	
					srcCat.pIdToProductMap			= getSourceProductsByPId(rqst,resp,'[XferPbe 1.2] Locate products in source org corresponding to source product List');
				if (tgtCat.skuToProductMap.size() == 0)	
					tgtCat.skuToProductMap			= getTargetProductsBySku(rqst,resp,'[XferPbe 1.3] Locate products in target org corresponding to source product List...');
					
				srcCat.stdPbSkuCurrencyToPbeMap		= getSourcePbeBySkuCurrency(rqst,resp,srcCat.pIdToProductMap, srcCat.stdPbId,	'[XferPbe 2.1] Locate std price book entries in source org');
				srcCat.customPbSkuCurrencyToPbeMap	= getSourcePbeBySkuCurrency(rqst,resp,srcCat.pIdToProductMap, srcCat.pbId, 		'[XferPbe 2.2] Locate custom price book entries in source org');
				tgtCat.stdPbSkuCurrencyToPbeMap		= getTargetPbeBySkuCurrency(rqst,resp, tgtCat.stdPbId,							'[XferPbe 2.3] Locate std price book entries in target org');
				tgtCat.customPbSkuCurrencyToPbeMap	= getTargetPbeBySkuCurrency(rqst,resp, tgtCat.pbId, 							'[XferPbe 2.4] Locate custom price book entries in target org');
				
				if (rqst.instr.isDebugEnabled)
					debug(resp,srcCat,tgtCat);
				tgtCat.stdPbSkuCurrencyToPbeMap		= upsertSourcePbeToTarget(rqst,resp,srcCat,tgtCat,true,	'[XferPbe 2.5] Upsert source PBE in std pricebook to target std pricebook');
				tgtCat.customPbSkuCurrencyToPbeMap	= upsertSourcePbeToTarget(rqst,resp,srcCat,tgtCat,false,'[XferPbe 2.6] Upsert source PBE in custom pricebook to target custom pricebook');
			}
			

					
		}
		catch (Exception e) {
			if (sp != null) Database.rollback(sp);
			resp.addError(e.getMessage() + ' ' + e.getStackTraceString());
			restResp.statusCode					= 400;
		}
		return resp;
	}
	
	//	----------------------------------------
	//	createTargetPricebook : Create a pricebook using all the fields supplied from the source org
	//	----------------------------------------
	private static ID createTargetPricebook(CatalogXferRequestResponse.Request rqst, CatalogXferRequestResponse.Response	resp,  String logMsg) {
		ID	res;
		resp.addLogMsg(logMsg);
		Pricebook2 pb	= rqst.pb.clone(false,true,false,false);
		insert pb;
		resp.addLogMsg('  Created ' + pb.name + ' in target org.');
		res 			= pb.id;
		return res;
	}
	
	//	-----------------------------------------
	//	debug
	//	-----------------------------------------
	private static void debug(CatalogXferRequestResponse.Response resp, Catalog srcCat, Catalog tgtCat) {						
		resp.addLogMsg('Source Catalog debug...');
		resp.addLogMsg(srcCat.debug());
		resp.addLogMsg('\n\nTarget Catalog debug...');
		resp.addLogMsg(tgtCat.debug());
	}
	
	//	-----------------------------------------
	//	getSourcePbeBySkuCurrency : For all the PBE in the source, create map by SKU+currency
	//	-----------------------------------------
	private static Map<String,PricebookEntry> getSourcePbeBySkuCurrency(CatalogXferRequestResponse.Request rqst, CatalogXferRequestResponse.Response resp,
																		 Map<String,Product2>	srcPIdToProductMap, ID pbId, String logMsg) {
		Map<String,PricebookEntry>		res		= new Map<String,PricebookEntry> ();
		resp.addLogMsg(logMsg);
		for (PricebookEntry pbe : rqst.pbeList)
			if (pbe.pricebook2Id == pbId)
				res.put(srcPIdToProductMap.get(pbe.product2Id).productCode + pbe.currencyIsoCode,pbe);
		resp.addLogMsg('  Created map of ' + res.size() + ' Source SKU+currency => Source PBE from list of  ' + rqst.pbeList.size() + ' Source org PricebookEntries in pricebookId ' + pbId +'.');
		return res;
	}
	
	//	-----------------------------------------
	//	getSourceProductsByPId : For all the SKUs in the source, create map by pId
	//	-----------------------------------------
	private static Map<String,Product2> getSourceProductsByPId(CatalogXferRequestResponse.Request rqst, CatalogXferRequestResponse.Response	resp,  String logMsg) {
		Map<String,Product2>		res		= new Map<String,Product2> ();
		resp.addLogMsg(logMsg);
		for (Product2 p : rqst.pList)
			res.put(p.id,p);
		resp.addLogMsg('  Created map of ' + res.size() + ' Source Pid => Source product from list of  ' + rqst.pList.size() + ' Source org SKUs.');
		return res;
	}	
	
	//	-----------------------------------------
	//	getTargetPbeBySkuCurrency : For all the SKUs in the target, locate the target org's PBE and build map by productCode+Currency to PBE
	//	-----------------------------------------
	private static Map<String,PricebookEntry> getTargetPbeBySkuCurrency(CatalogXferRequestResponse.Request rqst, CatalogXferRequestResponse.Response resp,
																		ID pbId, String logMsg) {
		Map<String,PricebookEntry>		res		= new Map<String,PricebookEntry> ();
		Set<String>		skuSearchSet		= new Set<String> ();
		resp.addLogMsg(logMsg);
		for (Product2 p : rqst.pList)
			skuSearchSet.add(p.productCode);
		for (PricebookEntry pbe : [select id, currencyIsoCode, isActive, pricebook2Id, product2Id, productCode, unitPrice, useStandardPrice 
										from PricebookEntry where productCode IN :skuSearchSet and
															pricebook2Id = :pbId ])
			res.put(pbe.productCode+pbe.currencyIsoCode,pbe);
		resp.addLogMsg(' Created map of ' + res.size() + ' target pricebook entries from list of ' + rqst.pList.size() + ' Source org pricebook entries.');		
		return res;
	}

	//	----------------------------------------
	//	getTargetPricebook : Locates pricebook in this (target org) using pricebook name in request
	//	----------------------------------------
	private static ID getTargetPricebook(CatalogXferRequestResponse.Request rqst, CatalogXferRequestResponse.Response	resp,  String logMsg) {
		ID	res;
		resp.addLogMsg(logMsg);
		try {
			res	= [select id, name from Pricebook2 where name = :rqst.pb.name limit 1].id;
			resp.addLogMsg('  Target org pricebook located with id = ' + res);
		}
		catch (QueryException e) {resp.addLogMsg('  Target org does not have pricebook.');}
		return res;
	}	
	
	//	-----------------------------------------
	//	getTargetProductsBySku : For all the SKUs in the source, locate the target org's Product2 and build map by ProductCode
	//	-----------------------------------------
	private static Map<String,Product2> getTargetProductsBySku(CatalogXferRequestResponse.Request rqst, CatalogXferRequestResponse.Response	resp,  String logMsg) {
		Map<String,Product2>		res		= new Map<String,Product2> ();
		Set<String>		skuSearchSet		= new Set<String> ();
		resp.addLogMsg(logMsg);
		for (Product2 p : rqst.pList)
			skuSearchSet.add(p.productCode);
			
		for (Product2 p : [select id, name, productCode from Product2 where productCode IN :skuSearchSet])
			res.put(p.productCode,p);
		resp.addLogMsg('  Located ' + res.size() + ' products in target org from search set of ' + skuSearchSet.size() + ' SKUs from source org.');
		return res;
	}
	

	
	
	//	-----------------------------------------
	//	removeLookupFields : Clone copies in lookup fields from source org, these will fail to upsert. Remove them.
	//	This method requires custom modification for the org in question based on the names of the lookup fields
	//	-----------------------------------------
	private static Product2 removeLookupFields(Product2 tgtP) {
		Product2	res 	= tgtP;
	//	res.customLookupField__c		= null;			// 	Custom field that is a lookup in Product2 to another Product2 (e.g. BOM use case)
														//	Add other custom lookup fields here and null them out
		return res;
	}

	//	-----------------------------------------
	//	upsertSourcePbeToTarget : Insert/Upsert (per smash instruction) the source pbe into target org for either std or custom pricebook
	//	-----------------------------------------
	private static Map<String,PricebookEntry> upsertSourcePbeToTarget(CatalogXferRequestResponse.Request rqst, CatalogXferRequestResponse.Response	resp,  Catalog srcCat, Catalog tgtCat, 
																		Boolean isStdPricebook, String logMsg) {
		
		resp.addLogMsg(logMsg);
		List<PricebookEntry>		pbeUpsertList	= new List<PricebookEntry> ();
		
		Map<String,PricebookEntry>	srcWorkSkuCurrencyToPbeMap	= isStdPricebook 
																? srcCat.stdPbSkuCurrencyToPbeMap
																: srcCat.customPbSkuCurrencyToPbeMap; 
		
		Map<String,PricebookEntry>	tgtWorkSkuCurrencyToPbeMap	= isStdPricebook 
																? tgtCat.stdPbSkuCurrencyToPbeMap
																: tgtCat.customPbSkuCurrencyToPbeMap;
																
		Map<String,PricebookEntry>	res				= tgtWorkSkuCurrencyToPbeMap;
		String						srcProductCode;	
															 
		for (PricebookEntry pbe : rqst.pbeList) {
			if (isStdPricebook && pbe.pricebook2Id != rqst.instr.stdPbId) continue;		// ignore custom pricebook pbe if doing std pricebook
			if (!isStdPricebook && pbe.pricebook2Id == rqst.instr.stdPbId) continue;	// ignore std pricebook pbe if doing custom pricebook
			srcProductCode							= srcCat.pIdToProductMap.get(pbe.product2Id).productCode;
			String key	= srcProductCode+pbe.currencyIsoCode;
			
			if (tgtWorkSkuCurrencyToPbeMap.containsKey(key) && !rqst.instr.smash)
				continue;																					// ignore source pbe in target org if smash is false
			
			
			if (!tgtCat.skuToProductMap.containsKey(srcProductCode)) {										// Ignore PBE xfers for products that don't exist in target
				resp.addLogMsg('  IGNORE pricebookEntry xfer request for ' + srcProductCode + '. SKU not yet transferred to target org.');
				continue;
			}
			
			//	Either source PBE is in target PBE or is new
			PricebookEntry pbeUpsert= new PricebookEntry(	id 					= tgtWorkSkuCurrencyToPbeMap.containsKey(key) ? tgtWorkSkuCurrencyToPbeMap.get(key).id : null,
															currencyIsoCode		= pbe.currencyIsoCode,
															isActive			= pbe.isActive,
															pricebook2Id		= isStdPricebook ? 	tgtCat.stdPbId : tgtCat.pbId,
															product2Id			= tgtCat.skuToProductMap.get(srcProductCode).id,
															unitPrice			= pbe.unitPrice,
															useStandardPrice	= pbe.useStandardPrice	
														);
			resp.addLogMsg('  Prepare to upsert PricebookEntry ' + srcProductCode + ' ' + pbe.currencyIsoCode + ' ' + pbe.unitPrice + (pbeUpsert.id == null ? ' [NEW]' : ' [UPDATE] ' + pbeUpsert.id));			
			pbeUpsertList.add(pbeUpsert);
		}
			
		upsert pbeUpsertList;
		
		List<PricebookEntry>	pbeUpsertResList = [select id, currencyisoCode, isActive, product2Id, pricebook2Id, productCode, unitPrice, useStandardPrice
														from PricebookEntry where id IN: pbeUpsertList];
		for (PricebookEntry pbe : pbeUpsertResList) {														// Update our target map so we have all the ids; needed for PBE updates
			res.put(pbe.ProductCode+pbe.currencyIsoCode,pbe);
		}
				
		resp.addLogMsg('  Upserted ' + pbeUpsertList.size() + ' pricebookEntries in target org from list of  ' + rqst.pbeList.size() + ' source org pricebookEntries. Smash was: ' + rqst.instr.smash);
		return res;
	}


	
	//	-----------------------------------------
	//	upsertSourceProductsToTarget : Insert/Upsert (per smash instruction) the source products into target org
	//	-----------------------------------------
	private static Map<String,Product2> upsertSourceProductsToTarget(CatalogXferRequestResponse.Request rqst, CatalogXferRequestResponse.Response	resp,  Catalog srcCat, Catalog tgtCat, String logMsg) {
		Map<String,Product2>		res		= tgtCat.skuToProductMap;
		resp.addLogMsg(logMsg);
		List<Product2>				pUpsertList		= new List<Product2> ();
		for (Product2 p : rqst.pList) {
			if (tgtCat.skuToProductMap.containsKey(p.productCode) && !rqst.instr.smash)
				continue;																					// ignore source products in target org if smash is false
			
			
			//	Either src product is already in target or it is new
			Product2 pUpsert	= srcCat.pIdToProductMap.get(p.id).clone(false,true,false,false);			// strip out id, do deep clone, ignore system fields and auto-number fields
			pUpsert				= removeLookupFields(pUpsert);												// clone copies in lookup fields that won't upsert, require second pass
			pUpsert.id			= tgtCat.skuToProductMap.containsKey(p.productCode)  
									? tgtCat.skuToProductMap.get(p.productCode).id							// clever, paste in id from target org on clone of source org data
									: null;																	// new product, not in target org
			pUpsertList.add(pUpsert);
			
		}
			
		upsert pUpsertList;
		
		for (Product2 p : pUpsertList) {																			// Update our target map so we have all the ids; needed for PBE updates
			res.put(p.productCode,p);
			resp.addLogMsg('  Upserted SKU ' + p.productCode);
		}
				
		resp.addLogMsg('  Upserted ' + pUpsertList.size() + ' products in target org from list of  ' + rqst.pList.size() + ' source org SKUs. Smash was: ' + rqst.instr.smash);
		return res;
	}
	
	
	//	----------------------------------------------------------------
	//	TESTMETHODS: Require access to std pricebook hence seeAllData=true
	//	----------------------------------------------------------------
	
	//	----------------------------------------------------------------
	//	testXferProducts
	//	----------------------------------------------------------------
	
	@isTest(SeeAllData=true)
	private static void testXferProducts() {
		
		
		//	0.1 Test no smash
/*		List<Product2>	pList	= TestSetup.setupProduct(new List<TestSetup.ProductPayload> {
																new TestSetup.ProductPayload ('00ProductSku',null,'00ProductDesc'),
																new TestSetup.ProductPayload ('01ProductSku',null,'01ProductDesc')
														}); */
		List<Product2>	pList	= new List<Product2> {											// tgt org Product2
																new Product2 (name = '00ProductSku', productCode = '00ProductSku', family = 'Test Family'),
																new Product2 (name = '01ProductSku', productCode = '01ProductSku', family = 'Test Family')
														}; 
		insert pList;	
		
		List<Product2>	dummyPList	= new List<Product2> {											// we need some valid ids for product2 objects in rqst payload
																new Product2 (name = '00DummySrcProductSku', productCode = '00ProductSku'),
																new Product2 (name = '01DummySrcProductSku', productCode = '01ProductSku'),
																new Product2 (name = '02DummySrcProductSku', productCode = '02ProductSku')
														}; 
		insert dummyPList;													
/*		List<Product2>	dummyPList	= TestSetup.setupProduct(new List<TestSetup.ProductPayload> {											// we need some valid ids for product2 objects in rqst payload
																new TestSetup.ProductPayload ('00DummySrcProductSku',null,'00ProductDesc'),
																new TestSetup.ProductPayload ('01DummySrcProductSku',null,'01ProductDesc'),
																new TestSetup.ProductPayload ('02DummySrcProductSku',null,'02ProductDesc')
														}); */												
		delete dummyPlist; 
		
		CatalogXferRequestResponse.Request rqst	= setupTestRequest(false,false,true,null, 		// no smash, no xfer pbe, xfer Product2, no srcStdPb
															new Pricebook2(name = 'srcPricebook'),		// doesnt matter as not used in this test
															new List<Product2> { 	new Product2(id = dummyPList[0].id, productCode = '00ProductSku', description = '00ProductDesc-fromsource', family='srcFamily',
																									name = '00ProductName'),
																					new Product2(id = dummyPList[2].id, productCode = '02ProductSku', description = '02ProductDesc-fromsource', family='srcFamily',
																									name = '02ProductName')
																				},
															new List<PricebookEntry> {}						
															);
		//		Src				Target		Exp Res
		//		00				00			unchanged
		//						01			unchanged
		//		02							added	
		List<String>	skuList		= new List<String> {'00ProductSku','01ProductSku','02ProductSku'};
		
		CatalogXferRequestResponse.Response	resp	= doPost(rqst);
		System.assertEquals(200,					resp.statusCode, resp.statusCode != 200 ? resp.statusMsg : '');
		
		List<Product2>	pResList					= [select id, productCode, name, family from Product2 where productCode IN :skuList order by productCode];
		System.assertEquals(3,						pResList.size(),pResList);
		System.assertEquals('Test Family',			pResList[0].family);			// unchanged
		System.assertEquals('Test Family',			pResList[1].family);			// unchanged
		System.assertEquals('srcFamily',			pResList[2].family);			// from source
		System.assertEquals('02ProductSku',			pResList[2].productCode);		// from source
		
		
		// 0.2 Test w/ smash
		delete pResList;
		
		pList	= new List<Product2> {											
																new Product2 (name = '00ProductSku', productCode = '00ProductSku', family = 'Test Family'),
																new Product2 (name = '01ProductSku', productCode = '01ProductSku', family = 'Test Family')
														}; 
		insert pList;
/*		pList	= TestSetup.setupProduct(new List<TestSetup.ProductPayload> {
																new TestSetup.ProductPayload ('00ProductSku',null,'00ProductDesc'),
																new TestSetup.ProductPayload ('01ProductSku',null,'01ProductDesc')
														}); */
		rqst.instr.smash							= true;
		resp	= doPost(rqst);
		System.assertEquals(200,					resp.statusCode, resp.statusCode != 200 ? resp.statusMsg : '');
		
		pResList									= [select id, productCode, name, family from Product2 where productCode IN :skuList order by productCode];
		System.assertEquals(3,						pResList.size(),pResList);
		System.assertEquals('srcFamily',			pResList[0].family);			// from source as we are smashing
		System.assertEquals('Test Family',			pResList[1].family);			// unchanged, [01] not in source
		System.assertEquals('srcFamily',			pResList[2].family);			// from source
		System.assertEquals('02ProductSku',			pResList[2].productCode);		// from source												
	}
		

	@isTest(SeeAllData=true)
	private static void testXferPbe() {
		//	0.1 Test target has products but not the pricebook or PBE
		List<Product2>	pList	= new List<Product2> {											// tgt org Product2
																new Product2 (name = '00ProductSku', productCode = '00ProductSku', family = 'Test Family'),
																new Product2 (name = '01ProductSku', productCode = '01ProductSku', family = 'Test Family')
														}; 
		insert pList;	
		
		List<Product2>	dummyPList	= new List<Product2> {											// we need some valid ids for product2 objects in rqst payload
																new Product2 (name = '00DummySrcProductSku', productCode = '00ProductSku'),
																new Product2 (name = '01DummySrcProductSku', productCode = '01ProductSku'),
																new Product2 (name = '02DummySrcProductSku', productCode = '02ProductSku')
														}; 
		insert dummyPList;													
		
		
/*		List<Product2>	pList	= TestSetup.setupProduct(new List<TestSetup.ProductPayload> {
																new TestSetup.ProductPayload ('00ProductSku',null,'00ProductDesc'),
																new TestSetup.ProductPayload ('01ProductSku',null,'01ProductDesc')
														});
														
		List<Product2>	dummyPList	= TestSetup.setupProduct(new List<TestSetup.ProductPayload> {											// we need some valid ids for product2 objects in rqst payload
																new TestSetup.ProductPayload ('00DummySrcProductSku',null,'00ProductDesc'),
																new TestSetup.ProductPayload ('01DummySrcProductSku',null,'01ProductDesc'),
																new TestSetup.ProductPayload ('02DummySrcProductSku',null,'02ProductDesc')
														}); 	*/											
		delete dummyPlist;												
		
		List<Pricebook2>	dummyPbList	= new List<Pricebook2> {new Pricebook2 (name = 'dummyStdPricebook'),								// we need valid Pricebook ids for source PBE payload
																new Pricebook2 (name = 'dummySrcPricebook')};
		insert dummyPbList;
		delete dummyPbList;	
		
		//	Test [0] - Xfer Pbe in AUD, all new

		
		CatalogXferRequestResponse.Request rqst	= setupTestRequest(false,true,false,dummyPbList[0].id, 		// no smash,  xfer pbe,  no xfer Product2, dumm src stdPbId
															new Pricebook2(id = dummyPBList[1].id, name = 'srcPricebook'),		// should get created by test in target
															new List<Product2> { 	new Product2(id = dummyPList[0].id, productCode = '00ProductSku', description = '00ProductDesc-fromsource', family='srcFamily',  	// 
																									name = '00ProductName'),
																					new Product2(id = dummyPList[1].id, productCode = '01ProductSku', description = '01ProductDesc-fromsource', family='srcFamily', 	// 
																									name = '01ProductName')
																				},
															new List<PricebookEntry> { 	new PricebookEntry (pricebook2Id = dummyPbList[0].id, product2Id = dummyPList[0].id, 
																											currencyIsoCode = 'AUD', isActive = true, unitPrice = 0.00, useStandardPrice= false),
																						new PricebookEntry (pricebook2Id = dummyPbList[1].id, product2Id = dummyPList[0].id, 
																											currencyIsoCode = 'AUD', isActive = true, unitPrice = 0.00, useStandardPrice= true),
																						new PricebookEntry (pricebook2Id = dummyPbList[0].id, product2Id = dummyPList[1].id, 
																											currencyIsoCode = 'AUD', isActive = true, unitPrice = 10.00, useStandardPrice= false),
																						new PricebookEntry (pricebook2Id = dummyPbList[1].id, product2Id = dummyPList[1].id, 
																											currencyIsoCode = 'AUD', isActive = true, unitPrice = 10.00, useStandardPrice= true)										
																											}						
															);
		//		Src				Target		Exp Res
		//		00 AUD			00 			added pbe in both std pb and custom pb
		//		01 AUD			01			added pbe in both std pb and custom pb	
		
		List<String>	skuList		= new List<String> {'00ProductSku','01ProductSku'};
		
		CatalogXferRequestResponse.Response	resp	= doPost(rqst);
		System.assertEquals(200,					resp.statusCode, resp.statusCode != 200 ? resp.statusMsg : '');
		
		List<Pricebook2>		pbResList			= [select id, name from pricebook2 where name = 'srcPricebook'];
		System.assertEquals(1,						pbResList.size(),resp.log);
		
		
		
		List<PricebookEntry>	pbeResList			= [select id, currencyIsoCode, pricebook2Id, pricebook2.name, product2Id, productCode, unitprice, useStandardPrice from PricebookEntry 
															where productCode IN :skuList order by useStandardPrice asc ,productCode asc ,currencyIsoCode asc];
		System.assertEquals(4,						pbeResList.size(),'Log:' + resp.log + '\npbeList=' + pbeResList);
		String		vRes;
		//									useStdPb	unitP	PbName						SKU			Currency	Ix
		vRes		= 	verifyPbe(pbeResList,  false, 	0.00, 	'Standard Price Book', 	'00ProductSku', 'AUD', 		0) +
						verifyPbe(pbeResList,  false, 	10.00, 	'Standard Price Book', 	'01ProductSku', 'AUD', 		1) +
						verifyPbe(pbeResList,  true, 	0.00, 	'srcPricebook', 		'00ProductSku', 'AUD', 		2) +
						verifyPbe(pbeResList,  true, 	10.00, 	'srcPricebook', 		'01ProductSku', 'AUD', 		3);
						
		System.assert(vRes.length() == 0,vRes+'\n'+resp.log);				 
		
		//	Test [1] - Xfer Add USD and smash AUD values
		rqst							= setupTestRequest(true,true,false,dummyPbList[0].id, 		//  smash,  xfer pbe,  no xfer Product2, dumm src stdPbId
															new Pricebook2(id = dummyPBList[1].id, name = 'srcPricebook'),		// should get created by test in target
															new List<Product2> { 	new Product2(id = dummyPList[0].id, productCode = '00ProductSku', description = '00ProductDesc-fromsource', family='srcFamily',  	// 
																									name = '00ProductName'),
																					new Product2(id = dummyPList[1].id, productCode = '01ProductSku', description = '01ProductDesc-fromsource', family='srcFamily', 	// 
																									name = '01ProductName')
																				},
															new List<PricebookEntry> { 	new PricebookEntry (pricebook2Id = dummyPbList[0].id, product2Id = dummyPList[0].id, 
																											currencyIsoCode = 'AUD', isActive = true, unitPrice = 100.00, useStandardPrice= false),
																						new PricebookEntry (pricebook2Id = dummyPbList[1].id, product2Id = dummyPList[0].id, 
																											currencyIsoCode = 'AUD', isActive = true, unitPrice = 100.00, useStandardPrice= true),
																						new PricebookEntry (pricebook2Id = dummyPbList[0].id, product2Id = dummyPList[1].id, 
																											currencyIsoCode = 'AUD', isActive = true, unitPrice = 110.00, useStandardPrice= false),
																						new PricebookEntry (pricebook2Id = dummyPbList[1].id, product2Id = dummyPList[1].id, 
																											currencyIsoCode = 'AUD', isActive = true, unitPrice = 110.00, useStandardPrice= true),
																						new PricebookEntry (pricebook2Id = dummyPbList[0].id, product2Id = dummyPList[0].id, 
																											currencyIsoCode = 'USD', isActive = true, unitPrice = 200.00, useStandardPrice= false),
																						new PricebookEntry (pricebook2Id = dummyPbList[1].id, product2Id = dummyPList[0].id, 
																											currencyIsoCode = 'USD', isActive = true, unitPrice = 200.00, useStandardPrice= true),
																						new PricebookEntry (pricebook2Id = dummyPbList[0].id, product2Id = dummyPList[1].id, 
																											currencyIsoCode = 'USD', isActive = true, unitPrice = 210.00, useStandardPrice= false),
																						new PricebookEntry (pricebook2Id = dummyPbList[1].id, product2Id = dummyPList[1].id, 
																											currencyIsoCode = 'USD', isActive = true, unitPrice = 210.00, useStandardPrice= true)															
																											}						
															);
		resp	= doPost(rqst);
		System.assertEquals(200,					resp.statusCode, resp.statusCode != 200 ? resp.statusMsg + '\n' + resp.log : '');
		
		pbResList					= [select id, name from pricebook2 where name = 'srcPricebook'];
		System.assertEquals(1,						pbResList.size(),resp.log);
		
		
		
		pbeResList					= [select id, currencyIsoCode, pricebook2Id, pricebook2.name, product2Id, productCode, unitprice, useStandardPrice from PricebookEntry 
															where productCode IN :skuList order by useStandardPrice asc ,productCode asc ,currencyIsoCode asc];
		System.assertEquals(8,						pbeResList.size(),'Log:' + resp.log + '\npbeList=' + pbeResList);
		//									useStdPb	unitP		PbName						SKU			Currency	Ix
		vRes		= 	verifyPbe(pbeResList,  false, 	100.00, 	'Standard Price Book', 	'00ProductSku', 'AUD', 		0) +
						verifyPbe(pbeResList,  false, 	200.00, 	'Standard Price Book', 	'00ProductSku', 'USD', 		1) +
						verifyPbe(pbeResList,  false, 	110.00, 	'Standard Price Book', 	'01ProductSku', 'AUD', 		2) +	
						verifyPbe(pbeResList,  false, 	210.00, 	'Standard Price Book', 	'01ProductSku', 'USD', 		3) +
						verifyPbe(pbeResList,  true, 	100.00, 	'srcPricebook', 		'00ProductSku', 'AUD', 		4) +
						verifyPbe(pbeResList,  true, 	200.00, 	'srcPricebook', 		'00ProductSku', 'USD', 		5) +
						verifyPbe(pbeResList,  true, 	110.00, 	'srcPricebook', 		'01ProductSku', 'AUD', 		6) +						
						verifyPbe(pbeResList,  true, 	210.00, 	'srcPricebook', 		'01ProductSku', 'USD', 		7);
						
		System.assert(vRes.length() == 0,vRes+'\n'+resp.log);
								
	}


	@isTest(SeeAllData=true)
	private static void testXferProductsAndPbe() {
													
		List<Product2>	dummyPList	= new List<Product2> {											// we need some valid ids for product2 objects in rqst payload
																new Product2 (name = '00DummySrcProductSku', productCode = '00ProductSku'),
																new Product2 (name = '01DummySrcProductSku', productCode = '01ProductSku'),
																new Product2 (name = '02DummySrcProductSku', productCode = '02ProductSku')
														}; 
		insert dummyPList;																								
		delete dummyPList;												
		
		List<Pricebook2>	dummyPbList	= new List<Pricebook2> {new Pricebook2 (name = 'dummyStdPricebook'),								// we need valid Pricebook ids for source PBE payload
																new Pricebook2 (name = 'dummySrcPricebook')};
		insert dummyPbList;
		delete dummyPbList;	
		
		//	Test [0] - Xfer Products and Pbe in AUD, all new including the SKUs
		
		CatalogXferRequestResponse.Request rqst	= setupTestRequest(false,true,true,dummyPbList[0].id, 		// no smash,  xfer pbe, xfer Product2, dumm src stdPbId
															new Pricebook2(id = dummyPBList[1].id, name = 'srcPricebook'),		// should get created by test in target
															new List<Product2> { 	new Product2(id = dummyPList[0].id, productCode = '00ProductSku', description = '00ProductDesc-fromsource', family='srcFamily',  	// 
																									name = '00ProductName'),
																					new Product2(id = dummyPList[1].id, productCode = '01ProductSku', description = '01ProductDesc-fromsource', family='srcFamily', 	// 
																									name = '01ProductName')
																				},
															new List<PricebookEntry> { 	new PricebookEntry (pricebook2Id = dummyPbList[0].id, product2Id = dummyPList[0].id, 
																											currencyIsoCode = 'AUD', isActive = true, unitPrice = 0.00, useStandardPrice= false),
																						new PricebookEntry (pricebook2Id = dummyPbList[1].id, product2Id = dummyPList[0].id, 
																											currencyIsoCode = 'AUD', isActive = true, unitPrice = 0.00, useStandardPrice= true),
																						new PricebookEntry (pricebook2Id = dummyPbList[0].id, product2Id = dummyPList[1].id, 
																											currencyIsoCode = 'AUD', isActive = true, unitPrice = 10.00, useStandardPrice= false),
																						new PricebookEntry (pricebook2Id = dummyPbList[1].id, product2Id = dummyPList[1].id, 
																											currencyIsoCode = 'AUD', isActive = true, unitPrice = 10.00, useStandardPrice= true)										
																											}						
															);
		//		Src				Target		Exp Res
		//		00							add SKU 00
		//		01							add SKU 01
		//		00 AUD			 			added  in both std pb and custom pb
		//		01 AUD						added  in both std pb and custom pb	
		
		List<String>	skuList		= new List<String> {'00ProductSku','01ProductSku'};
		
		CatalogXferRequestResponse.Response	resp	= doPost(rqst);
		System.assertEquals(200,					resp.statusCode, resp.statusCode != 200 ? resp.statusMsg + '\n' + resp.log : '');
		
		List<Pricebook2>		pbResList			= [select id, name from pricebook2 where name = 'srcPricebook'];
		System.assertEquals(1,						pbResList.size(),resp.log);
		
		List<Product2>	pResList					= [select id, productCode, name, family from Product2 where productCode IN :skuList order by productCode];
		System.assertEquals(2,						pResList.size(),pResList + '\n' + resp.log);
		
		List<PricebookEntry>	pbeResList			= [select id, currencyIsoCode, pricebook2Id, pricebook2.name, product2Id, productCode, unitprice, useStandardPrice from PricebookEntry 
															where productCode IN :skuList order by useStandardPrice asc ,productCode asc ,currencyIsoCode asc];
		System.assertEquals(4,						pbeResList.size(),'Log:' + resp.log + '\npbeList=' + pbeResList);
		String		vRes;
		//									useStdPb	unitP	PbName						SKU			Currency	Ix
		vRes		= 	verifyPbe(pbeResList,  false, 	0.00, 	'Standard Price Book', 	'00ProductSku', 'AUD', 		0) +
						verifyPbe(pbeResList,  false, 	10.00, 	'Standard Price Book', 	'01ProductSku', 'AUD', 		1) +
						verifyPbe(pbeResList,  true, 	0.00, 	'srcPricebook', 		'00ProductSku', 'AUD', 		2) +
						verifyPbe(pbeResList,  true, 	10.00, 	'srcPricebook', 		'01ProductSku', 'AUD', 		3);
						
		System.assert(vRes.length() == 0,vRes+'\n'+resp.log);				 
		
							
	}


		
	private static 	CatalogXferRequestResponse.Request setupTestRequest(Boolean smash, Boolean xferPbe, Boolean xferProduct, String srcStdPbId, Pricebook2 srcPb, List<Product2> srcPList, List<PricebookEntry> srcPbeList ) {
		//	Instantiate the System rest context objects 		
		System.RestRequest	restRqst					= new System.RestRequest();	
		System.RestResponse	restResp					= new System.RestResponse();																							
		restRqst.addHeader('Content-Type','application/json');
		restRqst.requestUri								= '/services/apexrest/catalogImport/V1/';
		restRqst.httpMethod								= 'POST';
		System.RestContext.request						= restRqst;
		System.RestContext.response						= restResp;
		
		//	Rathe than creating JSON test input; assume that it has deserialized into the Request and Instructions objects
		CatalogXferRequestResponse.Request		rqst	= new CatalogXferRequestResponse.Request();
		CatalogXferRequestResponse.Response		resp	= new CatalogXferRequestResponse.Response();
		CatalogXferRequestResponse.Instructions instr	= new CatalogXferRequestResponse.Instructions();
		
		instr.smash										= smash;
		instr.doXferPricebookEntries					= xferPbe;
		instr.doXferProducts							= xferProduct;
		instr.isDebugEnabled							= true;				// to help in diagnosis
		instr.stdPbId									= srcStdPbId;
		rqst.instr										= instr;
		rqst.pb											= srcPb;
		rqst.pList										= srcPList;
		rqst.pbeList									= srcPbeList;
		
		
		
		return rqst;	
	}
	
	private static String verifyPbe(PricebookEntry[] pbeResList, Boolean expUseStdPrice, Decimal expUnitPrice, String expPbName, String expProductCode, String expCurrencyIso, Integer ix)	{
	
	String		res ='';
	if (pbeResList[ix].useStandardPrice != expUseStdPrice)	res = res + '['+ix+'] useStdprice. Exp: ' 		+ expUseStdprice + ' vs actual ' 		+ pbeResList[ix].useStandardPrice + ' ';
	if (pbeResList[ix].unitPrice != expUnitPrice)			res = res + '['+ix+'] unitPrice. Exp: ' 		+ expUnitPrice + ' vs actual ' 			+ pbeResList[ix].unitPrice + ' ';
	if (pbeResList[ix].pricebook2.name != expPbName)		res = res + '['+ix+'] pbName. Exp: ' 			+ expPbName + ' vs actual ' 			+ pbeResList[ix].pricebook2.name + ' ';
	if (pbeResList[ix].productCode != expProductCode)		res = res + '['+ix+'] productCode. Exp: ' 		+ expProductCode + ' vs actual ' 		+ pbeResList[ix].productCode + ' ';
	if (pbeResList[ix].currencyIsoCode != expCurrencyIso)	res = res + '['+ix+'] useStdprice. Exp: ' 		+ expCurrencyIso + ' vs actual ' 		+ pbeResList[ix].currencyIsoCode + ' ';
	if (res.length() != 0)res = res + '\n';
	return res;											
	}
	
}