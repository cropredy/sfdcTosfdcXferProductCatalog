public abstract without sharing class ControllerBase {

	// Super class for common methods used by all standardController extensions and customControllers
	
	//	-----------------------------------------------------------------
	//			Common Properties available to all sub classes  
	//	-----------------------------------------------------------------
		
	public	Boolean							hasConstructorError	 {get; set;}		// used to communicate rendering instructions to VF pages
		
	//	------------------------------------------------------------------
	//			Common methods to all controllers and controllerExtensions
	//	------------------------------------------------------------------
	
	//	------------------------------------------------------------------
	//	getShowPageMessageDetail	: avoid showing pageMessages showdetail if every VF message detail = summary
	//	------------------------------------------------------------------
	public Boolean							getShowPageMessageDetail() {				
		for (ApexPages.Message msg : ApexPages.getMessages()) 
			if (msg.getSummary() != msg.getDetail()) return true;
		return false;	
	}
		
	//	---------------------------------------------------------------------
	//								CONSTRUCTOR
	//	---------------------------------------------------------------------
	public ControllerBase() {										// for default constructor of sub classes
	
		this.hasConstructorError	= false;				
	}
}