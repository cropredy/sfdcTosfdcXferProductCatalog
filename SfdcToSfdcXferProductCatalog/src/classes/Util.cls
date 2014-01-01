public with sharing class Util {
	// Utility methods

 	//  addVFPageMessage                            : Add a message to VF page of severity but clean up and otherwise not duplicate any message already in VF page context
 	//  flattenSearchIdSet                          : take set of Ids and turn into a comma-separated string of quoted ids suitable for dynamic SOQL
 	//  friendlifyException							: Throws away noise from Validation-rule generated exceptions
 	//	getAllSObjFieldNamesAsString				: For Dyn SOQL expressions
 	//  getStdPricebook                             : Singleton to remember stdPriceBook to avoid repeated SOQL calls
 	//  isExceptionAlreadyInVFMsgContext			: Checks to see if the exception is already registered by VF and hence we don't need to add it again
 	//  showVFMsgs  								: Return a formatted list of all VF messages in the current context
 	
 	
 	//	--------------------------------------------------------
 	//	Singleton static variables to avoid requerying throughout a complex transaction withmultiple classes/triggers
 	//	--------------------------------------------------------
 	
 	private static Map<String, Schema.SObjectType>          sobjToSobjDescribeMap;              // Singleton, remember when first referenced
 	private static Pricebook2                               stdPriceBook;                       // Singleton, remember when first referenced
 	
 	//  ----------------------------------------------
    //  addVFPageMessage
    //  ----------------------------------------------
    public static void addVFPageMessage(ApexPages.Severity sev, String msg, Exception e) {
        System.debug(LoggingLevel.INFO,'Util.addVFPageMessage' +
                            '\n  Severity                  : ' + sev +
                            '\n  Msg                       : ' + msg +
                            '\n  Exception                 : ' + Util.showException(e) +
                            '\n  VF Message(s) before      : ' + Util.showVFMsgs());
        
        if (!Util.isExceptionAlreadyInVFMsgContext(e))
                ApexPages.addMessage(new ApexPages.Message(sev,msg, 
                                                            (e != null && 
                                                             (e.getTypeName() == 'System.DmlException' ||
                                                              e.getTypeName() == 'CustomException'
                                                             )
                                                                ? Util.friendlifyException(e) 
                                                                : Util.showException(e)) 
                                                ));
        System.debug(LoggingLevel.INFO,'Util.addVFPageMessage' +
                            '\n  VF Message(s) after      : ' + Util.showVFMsgs());                                     
    }

 	// --------------------------------------------
    //   flattenSearchIdSet                 : take set of Ids and turn into a comma-separated string of quoted ids suitable for dynamic SOQL
    // ---------------------------------------------
    public static String flattenSearchIdSet(Set<ID> idSet, String delim) {
        Set<String>	stringSet = new Set<String> ();
        for (ID id : idSet) stringSet.add(id);
        return flattenSearchStringSet(stringSet,delim);
    }

    // --------------------------------------------
    //   flattenSearchStringSet                 : take set of Strings and turn into a comma-separated string of quoted strings suitable for dynamic SOQL
    // ---------------------------------------------
    public static String flattenSearchStringSet(Set<String> stringSet, String delim) {
        String res = '';
        for (String s: stringSet) res = res  + (res.length() > 0 ? delim : '') + '\'' + s + '\'' ;
        return res; 
    }
    
    @isTest
    private static void testFlattenSearchxxSet() {
    	System.assertEquals('\'abc\'' + ',' + '\'def\'' , flattenSearchStringSet(new Set<String> {'abc','def'},','));
    }


    //  ---------------------------------------
    //  friendlifyException: Throws away noise from Validation-rule generated exceptions
    //  ---------------------------------------
    public static String friendlifyException(Exception e) {
        System.debug(LoggingLevel.INFO,'Util.friendlifyException entered for ' + e.getMessage());
        String      errMsg          = e.getMessage();
        String      res             = errMsg;
        String      sysErrPrefix    = 'FIELD_CUSTOM_VALIDATION_EXCEPTION,';
        Integer sysErrPrefixIndex   = errMsg.lastIndexOf(sysErrPrefix);
        if (sysErrPrefixIndex != -1)  // Strip out user unfriendly message prefix
            res = errMsg.subString(sysErrPrefixIndex + sysErrPrefix.length());
        String      cstmErrPrefix    = 'CustomException';
        Integer cstmErrPrefixIndex   = errMsg.lastIndexOf(cstmErrPrefix);
        if (cstmErrPrefixIndex != -1)  // Strip out user unfriendly message prefix
            res = errMsg.subString(cstmErrPrefixIndex + cstmErrPrefix.length());  
        Integer stackTraceIndex     = res.indexOf('Class.');
        Integer npeIx               = res.indexOf('NullPointerException');
        if (stackTraceIndex != -1)   // Strip out the stack trace at end of some messages;
            res = res.subString(0,stackTraceIndex);
            
        if (npeIx != -1)            // add in stacktrace for certainException
            res = res + '\n' + e.getStackTraceString(); 
        System.debug(LoggingLevel.INFO,'Util.friendlifyException res= ' + res);
        return res;
    }

	//	-------------------------------------------------------
	//	getAllSObjFieldNamesAsString	: For Dyn SOQL expressions, returns 'fieldFoo__c, fieldBar__c, stdFieldC, ...'
	//	-------------------------------------------------------
	public static String getAllSObjFieldNamesAsString(String sObjName) {
		String		res;
		if (sobjToSobjDescribeMap == null) 
            sobjToSobjDescribeMap = Schema.getGlobalDescribe();                                                         // Step 0. Describe calls are limit bound; remember this for the next invocation

        Schema.Describesobjectresult        describe        =  sobjToSobjDescribeMap.get(sObjName).getDescribe();       //  Step 1. Locate all the fields in the sObject via Describe and fetch =   
        Map<String, Schema.SObjectField>    fieldMap        = describe.fields.getMap();                                 //  Step 2. Create a map of every fieldname: fieldtoken within sObject
        
        List<String>	fieldNameList	= new List<String> (fieldMap.keyset());
        res				= String.join(fieldNameList,','); 
        
		return res;
	}

	//  -------------------------------------------------------
    //  getStdPriceBook: Singleton
    //  -------------------------------------------------------
    public static Pricebook2    getStdPriceBook () {
        if (stdPriceBook == null) 
            stdPriceBook    = [select id, name from Pricebook2 where isStandard = true limit 1];
        return stdPriceBook;    
    }
    
    //  ----------------------------------------
    //  isExceptionAlreadyInVFMsgContext: Checks to see if the exception is already registered by VF and hence we don't need to add it again
    //  -----------------------------------------
    public static Boolean isExceptionAlreadyInVFMsgContext(Exception e) {
        Boolean res = false;
        
        if (e != null && !Test.isRunningTest()) {                       // only do this for PROD, not testmethods as they need to check for each error accumulated within testmethod
            for (ApexPages.Message m : ApexPages.getMessages())
                if (e.getMessage().contains(m.getSummary())) {
                    res = true; System.debug(LoggingLevel.INFO,'Util.isExceptionAlreadyInVFMsgContext.. Exception is in ApexPages already, return true'); break;}
        }
        System.debug(LoggingLevel.INFO,'Util.isExceptionAlreadyInVFMsgContext, res=' + res);
        return res;
    }
    
    //  ------------------------------------------
    //  showException	:
    //  ------------------------------------------
    public static String showException(Exception e) {
        return e != null ? e.getTypeName() + ' ' + e.getMessage() + ' line:' + e.getLineNumber() + '\n' + e.getStackTraceString() : '';  
    }
    
    // --------------------------------------------
    //  showVFMsgs  : Return a formatted list of all VF messages in the current context
    //  ------------------------------------------
    public static String showVFMsgs() {
        String          res         = '';
        for (Integer i = 0; i < ApexPages.getMessages().size(); i++)
            res = res + '\n' + '[' + i + '] ' + ApexPages.getMessages()[i].getSummary() + ' ' + ApexPages.getMessages()[i].getDetail();
        return res; 
    }
}