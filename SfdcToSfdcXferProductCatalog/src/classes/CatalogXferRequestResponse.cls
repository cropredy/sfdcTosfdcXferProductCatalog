global with sharing class CatalogXferRequestResponse {



	//	-----------------------------------------------
	//	INNER CLASS Instructions	- For passing parameters about how to do the import
	//	-----------------------------------------------
	public class Instructions {
		public Boolean							smash					= false;
		public Boolean							doXferPricebookEntries	= false;
		public Boolean							doXferProducts			= false;
		public Boolean							isDebugEnabled			= false;
		public String							stdPbId;
	}

	//	-----------------------------------------------
	//	INNER CLASS Response - SFDC Rest services will serialize result from this object back to client
	//	-----------------------------------------------
	
	global class Response {
		public String					cxr			= 'CatalogXferResponse';
		public Integer					statusCode	= 200;
		public String					statusMsg	= null;
		public String					log;
		
		public void addError(String msg) {
			this.statusCode							= 400;
			this.statusMsg							= msg;
		}
		
		public void addLogMsg(String msg)	{
			String htmlMsg	= msg.startsWith('[') ? '<b>'+msg+'</b>' : msg;	
			this.log = this.log == null ? htmlMsg : this.log + '\n' + htmlMsg;
		}
		
		public Boolean hasError() {return this.statusCode != 200;}
	}

	//	-----------------------------------------------
	//	INNER CLASS Request - SFDC Rest services will deserialize POST and PUT into an object of this class
	//	-----------------------------------------------
	
	global class Request {
		public Instructions				instr;
		public Pricebook2	 			pb;
		public List<Product2>			pList;
		public List<PricebookEntry>		pbeList;
	}

}