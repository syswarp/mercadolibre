USE [mercadolibre]
GO
/****** Object:  User [ml]    Script Date: 13/10/2020 11:34:47 ******/
CREATE USER [ml] FOR LOGIN [ml] WITH DEFAULT_SCHEMA=[dbo]
GO
/****** Object:  UserDefinedTableType [dbo].[Hierarchy]    Script Date: 13/10/2020 11:34:47 ******/
CREATE TYPE [dbo].[Hierarchy] AS TABLE(
	[element_id] [int] NOT NULL,
	[sequenceNo] [int] NULL,
	[parent_ID] [int] NULL,
	[Object_ID] [int] NULL,
	[NAME] [nvarchar](2000) NULL,
	[StringValue] [nvarchar](max) NOT NULL,
	[ValueType] [varchar](10) NOT NULL,
	PRIMARY KEY CLUSTERED 
(
	[element_id] ASC
)WITH (IGNORE_DUP_KEY = OFF)
)
GO
/****** Object:  UserDefinedFunction [dbo].[JSONEscaped]    Script Date: 13/10/2020 11:34:47 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[JSONEscaped] ( /* this is a simple utility function that takes a SQL String with all its clobber and outputs it as a sting with all the JSON escape sequences in it.*/
 @Unescaped NVARCHAR(MAX) --a string with maybe characters that will break json
 )
RETURNS NVARCHAR(MAX)
AS
BEGIN
  SELECT @Unescaped = REPLACE(@Unescaped, FROMString, TOString)
  FROM (SELECT '' AS FromString, '\' AS ToString 
        UNION ALL SELECT '"', '"' 
        UNION ALL SELECT '/', '/'
        UNION ALL SELECT CHAR(08),'b'
        UNION ALL SELECT CHAR(12),'f'
        UNION ALL SELECT CHAR(10),'n'
        UNION ALL SELECT CHAR(13),'r'
        UNION ALL SELECT CHAR(09),'t'
 ) substitutions
RETURN @Unescaped
END
GO
/****** Object:  UserDefinedFunction [dbo].[parseJSON]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create FUNCTION [dbo].[parseJSON]( @JSON NVARCHAR(MAX))
/**
Summary: >
  The code for the JSON Parser/Shredder will run in SQL Server 2005, 
  and even in SQL Server 2000 (with some modifications required).
 
  First the function replaces all strings with tokens of the form @Stringxx,
  where xx is the foreign key of the table variable where the strings are held.
  This takes them, and their potentially difficult embedded brackets, out of 
  the way. Names are  always strings in JSON as well as  string values.
 
  Then, the routine iteratively finds the next structure that has no structure 
  Contained within it, (and is, by definition the leaf structure), and parses it,
  replacing it with an object token of the form ‘@Objectxxx‘, or ‘@arrayxxx‘, 
  where xxx is the object id assigned to it. The values, or name/value pairs 
  are retrieved from the string table and stored in the hierarchy table. G
  radually, the JSON document is eaten until there is just a single root
  object left.
Author: PhilFactor
Date: 01/07/2010
Version: 
  Number: 4.6.2
  Date: 01/07/2019
  Why: case-insensitive version
Example: >
  Select * from parseJSON('{    "Person": 
      {
       "firstName": "John",
       "lastName": "Smith",
       "age": 25,
       "Address": 
           {
          "streetAddress":"21 2nd Street",
          "city":"New York",
          "state":"NY",
          "postalCode":"10021"
           },
       "PhoneNumbers": 
           {
           "home":"212 555-1234",
          "fax":"646 555-4567"
           }
        }
     }
  ')
Returns: >
  nothing
**/
	RETURNS @hierarchy TABLE
	  (
	   Element_ID INT IDENTITY(1, 1) NOT NULL, /* internal surrogate primary key gives the order of parsing and the list order */
	   SequenceNo [int] NULL, /* the place in the sequence for the element */
	   Parent_ID INT null, /* if the element has a parent then it is in this column. The document is the ultimate parent, so you can get the structure from recursing from the document */
	   Object_ID INT null, /* each list or object has an object id. This ties all elements to a parent. Lists are treated as objects here */
	   Name NVARCHAR(2000) NULL, /* the Name of the object */
	   StringValue NVARCHAR(MAX) NOT NULL,/*the string representation of the value of the element. */
	   ValueType VARCHAR(10) NOT null /* the declared type of the value represented as a string in StringValue*/
	  )
	  /*
 
	   */
	AS
	BEGIN
	  DECLARE
	    @FirstObject INT, --the index of the first open bracket found in the JSON string
	    @OpenDelimiter INT,--the index of the next open bracket found in the JSON string
	    @NextOpenDelimiter INT,--the index of subsequent open bracket found in the JSON string
	    @NextCloseDelimiter INT,--the index of subsequent close bracket found in the JSON string
	    @Type NVARCHAR(10),--whether it denotes an object or an array
	    @NextCloseDelimiterChar CHAR(1),--either a '}' or a ']'
	    @Contents NVARCHAR(MAX), --the unparsed contents of the bracketed expression
	    @Start INT, --index of the start of the token that you are parsing
	    @end INT,--index of the end of the token that you are parsing
	    @param INT,--the parameter at the end of the next Object/Array token
	    @EndOfName INT,--the index of the start of the parameter at end of Object/Array token
	    @token NVARCHAR(200),--either a string or object
	    @value NVARCHAR(MAX), -- the value as a string
	    @SequenceNo int, -- the sequence number within a list
	    @Name NVARCHAR(200), --the Name as a string
	    @Parent_ID INT,--the next parent ID to allocate
	    @lenJSON INT,--the current length of the JSON String
	    @characters NCHAR(36),--used to convert hex to decimal
	    @result BIGINT,--the value of the hex symbol being parsed
	    @index SMALLINT,--used for parsing the hex value
	    @Escape INT --the index of the next escape character
	    
	  DECLARE @Strings TABLE /* in this temporary table we keep all strings, even the Names of the elements, since they are 'escaped' in a different way, and may contain, unescaped, brackets denoting objects or lists. These are replaced in the JSON string by tokens representing the string */
	    (
	     String_ID INT IDENTITY(1, 1),
	     StringValue NVARCHAR(MAX)
	    )
	  SELECT--initialise the characters to convert hex to ascii
	    @characters='0123456789abcdefghijklmnopqrstuvwxyz',
	    @SequenceNo=0, --set the sequence no. to something sensible.
	  /* firstly we process all strings. This is done because [{} and ] aren't escaped in strings, which complicates an iterative parse. */
	    @Parent_ID=0;
	  WHILE 1=1 --forever until there is nothing more to do
	    BEGIN
	      SELECT
	        @start=PATINDEX('%[^a-zA-Z]["]%', @json collate SQL_Latin1_General_CP850_Bin);--next delimited string
	      IF @start=0 BREAK --no more so drop through the WHILE loop
	      IF SUBSTRING(@json, @start+1, 1)='"' 
	        BEGIN --Delimited Name
	          SET @start=@Start+1;
	          SET @end=PATINDEX('%[^\]["]%', RIGHT(@json, LEN(@json+'|')-@start) collate SQL_Latin1_General_CP850_Bin);
	        END
	      IF @end=0 --either the end or no end delimiter to last string
	        BEGIN-- check if ending with a double slash...
             SET @end=PATINDEX('%[\][\]["]%', RIGHT(@json, LEN(@json+'|')-@start) collate SQL_Latin1_General_CP850_Bin);
 		     IF @end=0 --we really have reached the end 
				BEGIN
				BREAK --assume all tokens found
				END
			END 
	      SELECT @token=SUBSTRING(@json, @start+1, @end-1)
	      --now put in the escaped control characters
	      SELECT @token=REPLACE(@token, FromString, ToString)
	      FROM
	        (SELECT           '\b', CHAR(08)
	         UNION ALL SELECT '\f', CHAR(12)
	         UNION ALL SELECT '\n', CHAR(10)
	         UNION ALL SELECT '\r', CHAR(13)
	         UNION ALL SELECT '\t', CHAR(09)
			 UNION ALL SELECT '\"', '"'
	         UNION ALL SELECT '\/', '/'
	        ) substitutions(FromString, ToString)
		SELECT @token=Replace(@token, '\\', '\')
	      SELECT @result=0, @escape=1
	  --Begin to take out any hex escape codes
	      WHILE @escape>0
	        BEGIN
	          SELECT @index=0,
	          --find the next hex escape sequence
	          @escape=PATINDEX('%\x[0-9a-f][0-9a-f][0-9a-f][0-9a-f]%', @token collate SQL_Latin1_General_CP850_Bin)
	          IF @escape>0 --if there is one
	            BEGIN
	              WHILE @index<4 --there are always four digits to a \x sequence   
	                BEGIN
	                  SELECT --determine its value
	                    @result=@result+POWER(16, @index)
	                    *(CHARINDEX(SUBSTRING(@token, @escape+2+3-@index, 1),
	                                @characters)-1), @index=@index+1 ;
	         
	                END
	                -- and replace the hex sequence by its unicode value
	              SELECT @token=STUFF(@token, @escape, 6, NCHAR(@result))
	            END
	        END
	      --now store the string away 
	      INSERT INTO @Strings (StringValue) SELECT @token
	      -- and replace the string with a token
	      SELECT @JSON=STUFF(@json, @start, @end+1,
	                    '@string'+CONVERT(NCHAR(5), @@identity))
	    END
	  -- all strings are now removed. Now we find the first leaf.  
	  WHILE 1=1  --forever until there is nothing more to do
	  BEGIN
	 
	  SELECT @Parent_ID=@Parent_ID+1
	  --find the first object or list by looking for the open bracket
	  SELECT @FirstObject=PATINDEX('%[{[[]%', @json collate SQL_Latin1_General_CP850_Bin)--object or array
	  IF @FirstObject = 0 BREAK
	  IF (SUBSTRING(@json, @FirstObject, 1)='{') 
	    SELECT @NextCloseDelimiterChar='}', @type='object'
	  ELSE 
	    SELECT @NextCloseDelimiterChar=']', @type='array'
	  SELECT @OpenDelimiter=@firstObject
	  WHILE 1=1 --find the innermost object or list...
	    BEGIN
	      SELECT
	        @lenJSON=LEN(@JSON+'|')-1
	  --find the matching close-delimiter proceeding after the open-delimiter
	      SELECT
	        @NextCloseDelimiter=CHARINDEX(@NextCloseDelimiterChar, @json,
	                                      @OpenDelimiter+1)
	  --is there an intervening open-delimiter of either type
	      SELECT @NextOpenDelimiter=PATINDEX('%[{[[]%',
	             RIGHT(@json, @lenJSON-@OpenDelimiter)collate SQL_Latin1_General_CP850_Bin)--object
	      IF @NextOpenDelimiter=0 
	        BREAK
	      SELECT @NextOpenDelimiter=@NextOpenDelimiter+@OpenDelimiter
	      IF @NextCloseDelimiter<@NextOpenDelimiter 
	        BREAK
	      IF SUBSTRING(@json, @NextOpenDelimiter, 1)='{' 
	        SELECT @NextCloseDelimiterChar='}', @type='object'
	      ELSE 
	        SELECT @NextCloseDelimiterChar=']', @type='array'
	      SELECT @OpenDelimiter=@NextOpenDelimiter
	    END
	  ---and parse out the list or Name/value pairs
	  SELECT
	    @contents=SUBSTRING(@json, @OpenDelimiter+1,
	                        @NextCloseDelimiter-@OpenDelimiter-1)
	  SELECT
	    @JSON=STUFF(@json, @OpenDelimiter,
	                @NextCloseDelimiter-@OpenDelimiter+1,
	                '@'+@type+CONVERT(NCHAR(5), @Parent_ID))
	  WHILE (PATINDEX('%[A-Za-z0-9@+.e]%', @contents collate SQL_Latin1_General_CP850_Bin))<>0 
	    BEGIN
	      IF @Type='object' --it will be a 0-n list containing a string followed by a string, number,boolean, or null
	        BEGIN
	          SELECT
	            @SequenceNo=0,@end=CHARINDEX(':', ' '+@contents)--if there is anything, it will be a string-based Name.
	          SELECT  @start=PATINDEX('%[^A-Za-z@][@]%', ' '+@contents collate SQL_Latin1_General_CP850_Bin)--AAAAAAAA
              SELECT @token=RTrim(Substring(' '+@contents, @start+1, @End-@Start-1)),
	            @endofName=PATINDEX('%[0-9]%', @token collate SQL_Latin1_General_CP850_Bin),
	            @param=RIGHT(@token, LEN(@token)-@endofName+1)
	          SELECT
	            @token=LEFT(@token, @endofName-1),
	            @Contents=RIGHT(' '+@contents, LEN(' '+@contents+'|')-@end-1)
	          SELECT  @Name=StringValue FROM @strings
	            WHERE string_id=@param --fetch the Name
	        END
	      ELSE 
	        SELECT @Name=null,@SequenceNo=@SequenceNo+1 
	      SELECT
	        @end=CHARINDEX(',', @contents)-- a string-token, object-token, list-token, number,boolean, or null
                IF @end=0
	        --HR Engineering notation bugfix start
	          IF ISNUMERIC(@contents) = 1
		    SELECT @end = LEN(@contents) + 1
	          Else
	        --HR Engineering notation bugfix end 
		  SELECT  @end=PATINDEX('%[A-Za-z0-9@+.e][^A-Za-z0-9@+.e]%', @contents+' ' collate SQL_Latin1_General_CP850_Bin) + 1
	       SELECT
	        @start=PATINDEX('%[^A-Za-z0-9@+.e][A-Za-z0-9@+.e]%', ' '+@contents collate SQL_Latin1_General_CP850_Bin)
	      --select @start,@end, LEN(@contents+'|'), @contents  
	      SELECT
	        @Value=RTRIM(SUBSTRING(@contents, @start, @End-@Start)),
	        @Contents=RIGHT(@contents+' ', LEN(@contents+'|')-@end)
	      IF SUBSTRING(@value, 1, 7)='@object' 
	        INSERT INTO @hierarchy
	          (Name, SequenceNo, Parent_ID, StringValue, Object_ID, ValueType)
	          SELECT @Name, @SequenceNo, @Parent_ID, SUBSTRING(@value, 8, 5),
	            SUBSTRING(@value, 8, 5), 'object' 
	      ELSE 
	        IF SUBSTRING(@value, 1, 6)='@array' 
	          INSERT INTO @hierarchy
	            (Name, SequenceNo, Parent_ID, StringValue, Object_ID, ValueType)
	            SELECT @Name, @SequenceNo, @Parent_ID, SUBSTRING(@value, 7, 5),
	              SUBSTRING(@value, 7, 5), 'array' 
	        ELSE 
	          IF SUBSTRING(@value, 1, 7)='@string' 
	            INSERT INTO @hierarchy
	              (Name, SequenceNo, Parent_ID, StringValue, ValueType)
	              SELECT @Name, @SequenceNo, @Parent_ID, StringValue, 'string'
	              FROM @strings
	              WHERE string_id=SUBSTRING(@value, 8, 5)
	          ELSE 
	            IF @value IN ('true', 'false') 
	              INSERT INTO @hierarchy
	                (Name, SequenceNo, Parent_ID, StringValue, ValueType)
	                SELECT @Name, @SequenceNo, @Parent_ID, @value, 'boolean'
	            ELSE
	              IF @value='null' 
	                INSERT INTO @hierarchy
	                  (Name, SequenceNo, Parent_ID, StringValue, ValueType)
	                  SELECT @Name, @SequenceNo, @Parent_ID, @value, 'null'
	              ELSE
	                IF PATINDEX('%[^0-9]%', @value collate SQL_Latin1_General_CP850_Bin)>0 
	                  INSERT INTO @hierarchy
	                    (Name, SequenceNo, Parent_ID, StringValue, ValueType)
	                    SELECT @Name, @SequenceNo, @Parent_ID, @value, 'real'
	                ELSE
	                  INSERT INTO @hierarchy
	                    (Name, SequenceNo, Parent_ID, StringValue, ValueType)
	                    SELECT @Name, @SequenceNo, @Parent_ID, @value, 'int'
	      if @Contents=' ' Select @SequenceNo=0
	    END
	  END
	INSERT INTO @hierarchy (Name, SequenceNo, Parent_ID, StringValue, Object_ID, ValueType)
	  SELECT '-',1, NULL, '', @Parent_ID-1, @type
	--
	   RETURN
	END
GO
/****** Object:  UserDefinedFunction [dbo].[StrZero]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[StrZero](@cadena varchar(100), @intLen Int) 

RETURNS varchar(100)
AS
BEGIN

IF @intlen > 24
   SET @intlen = 24

RETURN REPLICATE('0',@intLen-LEN(RTRIM(@cadena))) 
    + @cadena
END

GO
/****** Object:  UserDefinedFunction [dbo].[ToXML]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[ToXML]
(
/*this function converts a Hierarchy table into an XML document. This uses the same technique as the toJSON function, and uses the 'entities' form of XML syntax to give a compact rendering of the structure */
      @Hierarchy Hierarchy READONLY
)
RETURNS NVARCHAR(MAX)--use unicode.
AS
BEGIN
  DECLARE
    @XMLAsString NVARCHAR(MAX),
    @NewXML NVARCHAR(MAX),
    @Entities NVARCHAR(MAX),
    @Objects NVARCHAR(MAX),
    @Name NVARCHAR(200),
    @Where INT,
    @ANumber INT,
    @notNumber INT,
    @indent INT,
    @CrLf CHAR(2)--just a simple utility to save typing!
      
  --firstly get the root token into place 
  --firstly get the root token into place 
  SELECT @CrLf=CHAR(13)+CHAR(10),--just CHAR(10) in UNIX
         @XMLasString ='<?xml version="1.0" ?>
@Object'+CONVERT(VARCHAR(5),OBJECT_ID)+'
'
    FROM @hierarchy 
    WHERE parent_id IS NULL AND valueType IN ('object','array') --get the root element
/* now we simply iterate from the root token growing each branch and leaf in each iteration. This won't be enormously quick, but it is simple to do. All values, or name/value pairs within a structure can be created in one SQL Statement*/
  WHILE 1=1
    begin
    SELECT @where= PATINDEX('%[^a-zA-Z0-9]@Object%',@XMLAsString)--find NEXT token
    if @where=0 BREAK
    /* this is slightly painful. we get the indent of the object we've found by looking backwards up the string */ 
    SET @indent=CHARINDEX(char(10)+char(13),Reverse(LEFT(@XMLasString,@where))+char(10)+char(13))-1
    SET @NotNumber= PATINDEX('%[^0-9]%', RIGHT(@XMLasString,LEN(@XMLAsString+'|')-@Where-8)+' ')--find NEXT token
    SET @Entities=NULL --this contains the structure in its XML form
    SELECT @Entities=COALESCE(@Entities+' ',' ')+NAME+'="'
     +REPLACE(REPLACE(REPLACE(StringValue, '<', '&lt;'), '&', '&amp;'),'>', '&gt;')
     + '"'  
       FROM @hierarchy 
       WHERE parent_id= SUBSTRING(@XMLasString,@where+8, @Notnumber-1) 
          AND ValueType NOT IN ('array', 'object')
    SELECT @Entities=COALESCE(@entities,''),@Objects='',@name=CASE WHEN Name='-' THEN 'root' ELSE NAME end
      FROM @hierarchy 
      WHERE [Object_id]= SUBSTRING(@XMLasString,@where+8, @Notnumber-1) 
    
    SELECT  @Objects=@Objects+@CrLf+SPACE(@indent+2)
           +'@Object'+CONVERT(VARCHAR(5),OBJECT_ID)
           --+@CrLf+SPACE(@indent+2)+''
      FROM @hierarchy 
      WHERE parent_id= SUBSTRING(@XMLasString,@where+8, @Notnumber-1) 
      AND ValueType IN ('array', 'object')
    IF @Objects='' --if it is a lef, we can do a more compact rendering
         SELECT @NewXML='<'+COALESCE(@name,'item')+@entities+' />'
    ELSE
        SELECT @NewXML='<'+COALESCE(@name,'item')+@entities+'>'
            +@Objects+@CrLf++SPACE(@indent)+'</'+COALESCE(@name,'item')+'>'
     /* basically, we just lookup the structure based on the ID that is appended to the @Object token. Simple eh? */
    --now we replace the token with the structure, maybe with more tokens in it.
    Select @XMLasString=STUFF (@XMLasString, @where+1, 8+@NotNumber-1, @NewXML)
    end
  return @XMLasString
  end
GO
/****** Object:  Table [dbo].[envios]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[envios](
	[001date_cancelled] [varchar](500) NULL,
	[002date_delivered] [varchar](500) NULL,
	[003date_first_visit] [varchar](500) NULL,
	[004date_handling] [varchar](500) NULL,
	[005date_not_delivered] [varchar](500) NULL,
	[006date_ready_to_ship] [varchar](500) NULL,
	[007date_shipped] [varchar](500) NULL,
	[008date_returned] [varchar](500) NULL,
	[009id] [varchar](500) NULL,
	[010name] [varchar](500) NULL,
	[011id] [varchar](500) NULL,
	[012name] [varchar](500) NULL,
	[013id] [varchar](500) NULL,
	[014name] [varchar](500) NULL,
	[015id] [varchar](500) NULL,
	[016name] [varchar](500) NULL,
	[017id] [varchar](500) NULL,
	[018name] [varchar](500) NULL,
	[023id] [varchar](500) NULL,
	[024address_line] [varchar](500) NULL,
	[025street_name] [varchar](500) NULL,
	[026street_number] [varchar](500) NULL,
	[027comment] [varchar](500) NULL,
	[028zip_code] [varchar](500) NULL,
	[029city] [varchar](500) NULL,
	[030state] [varchar](500) NULL,
	[031country] [varchar](500) NULL,
	[032neighborhood] [varchar](500) NULL,
	[033municipality] [varchar](500) NULL,
	[034agency] [varchar](500) NULL,
	[035types] [varchar](500) NULL,
	[036latitude] [varchar](500) NULL,
	[037longitude] [varchar](500) NULL,
	[038geolocation_type] [varchar](500) NULL,
	[039geolocation_last_updated] [varchar](500) NULL,
	[040geolocation_source] [varchar](500) NULL,
	[041id] [varchar](500) NULL,
	[042name] [varchar](500) NULL,
	[043id] [varchar](500) NULL,
	[044name] [varchar](500) NULL,
	[045id] [varchar](500) NULL,
	[046name] [varchar](500) NULL,
	[047id] [varchar](500) NULL,
	[048name] [varchar](500) NULL,
	[049id] [varchar](500) NULL,
	[050name] [varchar](500) NULL,
	[052id] [varchar](500) NULL,
	[053address_line] [varchar](500) NULL,
	[054street_name] [varchar](500) NULL,
	[055street_number] [varchar](500) NULL,
	[056comment] [varchar](500) NULL,
	[057zip_code] [varchar](500) NULL,
	[058city] [varchar](500) NULL,
	[059state] [varchar](500) NULL,
	[060country] [varchar](500) NULL,
	[061neighborhood] [varchar](500) NULL,
	[062municipality] [varchar](500) NULL,
	[063agency] [varchar](500) NULL,
	[064types] [varchar](500) NULL,
	[065latitude] [varchar](500) NULL,
	[066longitude] [varchar](500) NULL,
	[067geolocation_type] [varchar](500) NULL,
	[068geolocation_last_updated] [varchar](500) NULL,
	[069geolocation_source] [varchar](500) NULL,
	[070delivery_preference] [varchar](500) NULL,
	[071receiver_name] [varchar](500) NULL,
	[072receiver_phone] [varchar](500) NULL,
	[073id] [varchar](500) NULL,
	[074origin] [varchar](500) NULL,
	[075id] [varchar](500) NULL,
	[076description] [varchar](500) NULL,
	[077quantity] [varchar](500) NULL,
	[078dimensions] [varchar](500) NULL,
	[079dimensions_source] [varchar](500) NULL,
	[081date] [varchar](500) NULL,
	[082date] [varchar](500) NULL,
	[083date] [varchar](500) NULL,
	[084shipping] [varchar](500) NULL,
	[085from] [varchar](500) NULL,
	[086to] [varchar](500) NULL,
	[087type] [varchar](500) NULL,
	[088date] [varchar](500) NULL,
	[089unit] [varchar](500) NULL,
	[090offset] [varchar](500) NULL,
	[091time_frame] [varchar](500) NULL,
	[092pay_before] [varchar](500) NULL,
	[093shipping] [varchar](500) NULL,
	[094handling] [varchar](500) NULL,
	[095schedule] [varchar](500) NULL,
	[096date] [varchar](500) NULL,
	[097offset] [varchar](500) NULL,
	[098date] [varchar](500) NULL,
	[099offset] [varchar](500) NULL,
	[100date] [varchar](500) NULL,
	[101offset] [varchar](500) NULL,
	[102date] [varchar](500) NULL,
	[103id] [varchar](500) NULL,
	[104shipping_method_id] [varchar](500) NULL,
	[105name] [varchar](500) NULL,
	[106currency_id] [varchar](500) NULL,
	[107list_cost] [varchar](500) NULL,
	[108cost] [varchar](500) NULL,
	[109delivery_type] [varchar](500) NULL,
	[110estimated_schedule_limit] [varchar](500) NULL,
	[111buffering] [varchar](500) NULL,
	[112estimated_delivery_time] [varchar](500) NULL,
	[113estimated_delivery_limit] [varchar](500) NULL,
	[114estimated_delivery_final] [varchar](500) NULL,
	[115estimated_delivery_extended] [varchar](500) NULL,
	[116estimated_handling_limit] [varchar](500) NULL,
	[117special_discount] [varchar](500) NULL,
	[118loyal_discount] [varchar](500) NULL,
	[119compensation] [varchar](500) NULL,
	[120gap_discount] [varchar](500) NULL,
	[121ratio] [varchar](500) NULL,
	[122id] [varchar](500) NULL,
	[123mode] [varchar](500) NULL,
	[124created_by] [varchar](500) NULL,
	[125order_id] [varchar](200) NOT NULL,
	[126order_cost] [varchar](500) NULL,
	[127base_cost] [varchar](500) NULL,
	[128site_id] [varchar](500) NULL,
	[129status] [varchar](500) NULL,
	[130substatus] [varchar](500) NULL,
	[131status_history] [varchar](500) NULL,
	[132substatus_history] [varchar](500) NULL,
	[133date_created] [varchar](500) NULL,
	[134last_updated] [varchar](500) NULL,
	[135tracking_number] [varchar](500) NULL,
	[136tracking_method] [varchar](500) NULL,
	[137service_id] [varchar](500) NULL,
	[138carrier_info] [varchar](500) NULL,
	[139sender_id] [varchar](500) NULL,
	[140sender_address] [varchar](500) NULL,
	[141receiver_id] [varchar](500) NULL,
	[142receiver_address] [varchar](500) NULL,
	[143shipping_items] [varchar](500) NULL,
	[144shipping_option] [varchar](500) NULL,
	[145comments] [varchar](500) NULL,
	[146date_first_printed] [varchar](500) NULL,
	[147market_place] [varchar](500) NULL,
	[148return_details] [varchar](500) NULL,
	[149tags] [varchar](500) NULL,
	[150type] [varchar](500) NULL,
	[151logistic_type] [varchar](500) NULL,
	[152application_id] [varchar](500) NULL,
	[153return_tracking_number] [varchar](500) NULL,
	[154cost_components] [varchar](500) NULL,
	[155-] [varchar](500) NULL,
	[fechaalt] [datetime] NULL,
 CONSTRAINT [PK_envios] PRIMARY KEY CLUSTERED 
(
	[125order_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[mlapis]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[mlapis](
	[orden] [numeric](18, 0) NOT NULL,
	[descripcion] [varchar](200) NOT NULL,
	[call_api] [varchar](2000) NOT NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[ordenes_de_pedido]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[ordenes_de_pedido](
	[001sale] [varchar](200) NULL,
	[002purchase] [varchar](200) NULL,
	[003return] [varchar](200) NULL,
	[004change] [varchar](200) NULL,
	[005id] [varchar](200) NULL,
	[006amount] [varchar](200) NULL,
	[007id] [varchar](200) NOT NULL,
	[008title] [varchar](200) NULL,
	[009category_id] [varchar](200) NULL,
	[010variation_id] [varchar](200) NULL,
	[011seller_custom_field] [varchar](200) NULL,
	[012variation_attributes] [varchar](200) NULL,
	[013warranty] [varchar](200) NULL,
	[014condition] [varchar](200) NULL,
	[015seller_sku] [varchar](200) NOT NULL,
	[016global_price] [varchar](200) NULL,
	[017item] [varchar](200) NULL,
	[018quantity] [varchar](200) NULL,
	[019unit_price] [varchar](200) NULL,
	[020full_unit_price] [varchar](200) NULL,
	[021currency_id] [varchar](200) NULL,
	[022manufacturing_days] [varchar](200) NULL,
	[023sale_fee] [varchar](200) NULL,
	[024listing_type_id] [varchar](200) NULL,
	[026id] [varchar](200) NULL,
	[027company_id] [varchar](200) NULL,
	[028transaction_id] [varchar](200) NULL,
	[030id] [varchar](200) NULL,
	[031order_id] [varchar](200) NULL,
	[032payer_id] [varchar](200) NULL,
	[033collector] [varchar](200) NULL,
	[034card_id] [varchar](200) NULL,
	[035site_id] [varchar](200) NULL,
	[036reason] [varchar](200) NULL,
	[037payment_method_id] [varchar](200) NULL,
	[038currency_id] [varchar](200) NULL,
	[039installments] [varchar](200) NULL,
	[040issuer_id] [varchar](200) NULL,
	[041atm_transfer_reference] [varchar](200) NULL,
	[042coupon_id] [varchar](200) NULL,
	[043activation_uri] [varchar](200) NULL,
	[044operation_type] [varchar](200) NULL,
	[045payment_type] [varchar](200) NULL,
	[046available_actions] [varchar](200) NULL,
	[047status] [varchar](200) NULL,
	[048status_code] [varchar](200) NULL,
	[049status_detail] [varchar](200) NULL,
	[050transaction_amount] [varchar](200) NULL,
	[051taxes_amount] [varchar](200) NULL,
	[052shipping_cost] [varchar](200) NULL,
	[053coupon_amount] [varchar](200) NULL,
	[054overpaid_amount] [varchar](200) NULL,
	[055total_paid_amount] [varchar](200) NULL,
	[056installment_amount] [varchar](200) NULL,
	[057deferred_period] [varchar](200) NULL,
	[058date_approved] [varchar](200) NULL,
	[059authorization_code] [varchar](200) NULL,
	[060transaction_order_id] [varchar](200) NULL,
	[061date_created] [varchar](200) NULL,
	[062date_last_modified] [varchar](200) NULL,
	[064id] [varchar](200) NULL,
	[067doc_type] [varchar](200) NULL,
	[068doc_number] [varchar](200) NULL,
	[069id] [varchar](200) NULL,
	[070nickname] [varchar](200) NULL,
	[071email] [varchar](200) NULL,
	[072first_name] [varchar](200) NULL,
	[073last_name] [varchar](200) NULL,
	[074billing_info] [varchar](200) NULL,
	[075area_code] [varchar](200) NULL,
	[076extension] [varchar](200) NULL,
	[077number] [varchar](200) NULL,
	[078verified] [varchar](200) NULL,
	[079area_code] [varchar](200) NULL,
	[080extension] [varchar](200) NULL,
	[081number] [varchar](200) NULL,
	[082id] [varchar](200) NULL,
	[083nickname] [varchar](200) NULL,
	[084email] [varchar](200) NULL,
	[085first_name] [varchar](200) NULL,
	[086last_name] [varchar](200) NULL,
	[087phone] [varchar](200) NULL,
	[088alternative_phone] [varchar](200) NULL,
	[089amount] [varchar](200) NULL,
	[090currency_id] [varchar](200) NULL,
	[091id] [varchar](200) NULL,
	[092date_created] [varchar](200) NULL,
	[093date_closed] [varchar](200) NULL,
	[094last_updated] [varchar](200) NULL,
	[095manufacturing_ending_date] [varchar](200) NULL,
	[096feedback] [varchar](200) NULL,
	[097mediations] [varchar](200) NULL,
	[098comments] [varchar](200) NULL,
	[099pack_id] [varchar](200) NULL,
	[100pickup_id] [varchar](200) NULL,
	[101order_request] [varchar](200) NULL,
	[102fulfilled] [varchar](200) NULL,
	[103total_amount] [varchar](200) NULL,
	[104paid_amount] [varchar](200) NULL,
	[105coupon] [varchar](200) NULL,
	[106expiration_date] [varchar](200) NULL,
	[107order_items] [varchar](200) NULL,
	[108currency_id] [varchar](200) NULL,
	[109payments] [varchar](200) NULL,
	[110shipping] [varchar](200) NULL,
	[111status] [varchar](200) NULL,
	[112status_detail] [varchar](200) NULL,
	[113tags] [varchar](200) NULL,
	[114buyer] [varchar](200) NULL,
	[115seller] [varchar](200) NULL,
	[116taxes] [varchar](200) NULL,
	[117-] [varchar](200) NULL,
	[fechaalt] [datetime] NULL,
 CONSTRAINT [PK_ordenes_de_pedido] PRIMARY KEY CLUSTERED 
(
	[007id] ASC,
	[015seller_sku] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[orders]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[orders](
	[activation_uri] [varchar](500) NULL,
	[alternative_phone] [varchar](500) NULL,
	[amount] [varchar](500) NULL,
	[application_id] [varchar](500) NULL,
	[area_code] [varchar](500) NULL,
	[atm_transfer_reference] [varchar](500) NULL,
	[authorization_code] [varchar](500) NULL,
	[available_actions] [varchar](500) NULL,
	[available_sorts] [varchar](500) NULL,
	[billing_info] [varchar](500) NULL,
	[buyer] [varchar](500) NULL,
	[cancel_detail] [varchar](500) NULL,
	[card_id] [varchar](500) NULL,
	[category_id] [varchar](500) NULL,
	[cause] [varchar](500) NULL,
	[change] [varchar](500) NULL,
	[code] [varchar](500) NULL,
	[collector] [varchar](500) NULL,
	[comments] [varchar](500) NULL,
	[company_id] [varchar](500) NULL,
	[condition] [varchar](500) NULL,
	[coupon] [varchar](500) NULL,
	[coupon_amount] [varchar](500) NULL,
	[coupon_id] [varchar](500) NULL,
	[currency_id] [varchar](500) NULL,
	[current_responsible] [varchar](500) NULL,
	[date] [varchar](500) NULL,
	[date_approved] [varchar](500) NULL,
	[date_closed] [varchar](500) NULL,
	[date_created] [varchar](500) NULL,
	[date_last_modified] [varchar](500) NULL,
	[date_last_updated] [varchar](500) NULL,
	[deferred_period] [varchar](500) NULL,
	[description] [varchar](500) NULL,
	[display] [varchar](500) NULL,
	[doc_number] [varchar](500) NULL,
	[doc_type] [varchar](500) NULL,
	[email] [varchar](500) NULL,
	[error] [varchar](500) NULL,
	[expiration_date] [varchar](500) NULL,
	[extension] [varchar](500) NULL,
	[feedback] [varchar](500) NULL,
	[filters] [varchar](500) NULL,
	[first_name] [varchar](500) NULL,
	[fulfilled] [varchar](500) NULL,
	[full_unit_price] [varchar](500) NULL,
	[global_price] [varchar](500) NULL,
	[group] [varchar](500) NULL,
	[id] [varchar](500) NULL,
	[installment_amount] [varchar](500) NULL,
	[installments] [varchar](500) NULL,
	[interactions] [varchar](500) NULL,
	[issuer_id] [varchar](500) NULL,
	[item] [varchar](500) NULL,
	[last_name] [varchar](500) NULL,
	[last_updated] [varchar](500) NULL,
	[limit] [varchar](500) NULL,
	[listing_type_id] [varchar](500) NULL,
	[manufacturing_days] [varchar](500) NULL,
	[manufacturing_ending_date] [varchar](500) NULL,
	[mediations] [varchar](500) NULL,
	[message] [varchar](500) NULL,
	[name] [varchar](500) NULL,
	[nickname] [varchar](500) NULL,
	[number] [varchar](500) NULL,
	[offset] [varchar](500) NULL,
	[operation_type] [varchar](500) NULL,
	[order_id] [varchar](500) NULL,
	[order_items] [varchar](500) NULL,
	[order_request] [varchar](500) NULL,
	[overpaid_amount] [varchar](500) NULL,
	[pack_id] [varchar](500) NULL,
	[paging] [varchar](500) NULL,
	[paid_amount] [varchar](500) NULL,
	[payer_id] [varchar](500) NULL,
	[payment_method_id] [varchar](500) NULL,
	[payment_type] [varchar](500) NULL,
	[payments] [varchar](500) NULL,
	[phone] [varchar](500) NULL,
	[pickup_id] [varchar](500) NULL,
	[purchase] [varchar](500) NULL,
	[quantity] [varchar](500) NULL,
	[query] [varchar](500) NULL,
	[reason] [varchar](500) NULL,
	[requested_by] [varchar](500) NULL,
	[results] [varchar](500) NULL,
	[return] [varchar](500) NULL,
	[sale] [varchar](500) NULL,
	[sale_fee] [varchar](500) NULL,
	[seller] [varchar](500) NULL,
	[seller_custom_field] [varchar](500) NULL,
	[seller_sku] [varchar](500) NULL,
	[shipping] [varchar](500) NULL,
	[shipping_cost] [varchar](500) NULL,
	[site_id] [varchar](500) NULL,
	[sort] [varchar](500) NULL,
	[status] [varchar](500) NULL,
	[status_code] [varchar](500) NULL,
	[status_detail] [varchar](500) NULL,
	[tags] [varchar](500) NULL,
	[taxes] [varchar](500) NULL,
	[taxes_amount] [varchar](500) NULL,
	[title] [varchar](500) NULL,
	[total] [varchar](500) NULL,
	[total_amount] [varchar](500) NULL,
	[total_paid_amount] [varchar](500) NULL,
	[transaction_amount] [varchar](500) NULL,
	[transaction_id] [varchar](500) NULL,
	[transaction_order_id] [varchar](500) NULL,
	[unit_price] [varchar](500) NULL,
	[value_id] [varchar](500) NULL,
	[value_name] [varchar](500) NULL,
	[variation_attributes] [varchar](500) NULL,
	[variation_id] [varchar](500) NULL,
	[verified] [varchar](500) NULL,
	[warranty] [varchar](500) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[raw_json_orders]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[raw_json_orders](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[json_text] [text] NULL,
	[json_order] [text] NULL,
	[fecha] [datetime] NOT NULL,
	[procesado] [varchar](1) NULL,
 CONSTRAINT [raw_json_orders_pkey] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[raw_json_orders_detail]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[raw_json_orders_detail](
	[id] [numeric](18, 0) IDENTITY(1,1) NOT NULL,
	[json_text] [text] NULL,
	[json_order] [text] NULL,
	[fecha] [datetime] NULL,
	[procesado] [varchar](1) NULL,
	[order_id] [varchar](50) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[raw_json_orders_detail_table]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[raw_json_orders_detail_table](
	[Element_ID] [numeric](18, 0) NULL,
	[SequenceNo] [numeric](18, 0) NULL,
	[Parent_ID] [numeric](18, 0) NULL,
	[Object_ID] [numeric](18, 0) NULL,
	[Name] [varchar](500) NULL,
	[StringValue] [varchar](500) NULL,
	[ValueType] [varchar](50) NULL,
	[id] [numeric](18, 0) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[raw_json_orders_table]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[raw_json_orders_table](
	[Element_ID] [numeric](18, 0) NULL,
	[SequenceNo] [numeric](18, 0) NULL,
	[Parent_ID] [numeric](18, 0) NULL,
	[Object_ID] [numeric](18, 0) NULL,
	[Name] [varchar](500) NULL,
	[StringValue] [varchar](500) NULL,
	[ValueType] [varchar](50) NULL,
	[id] [numeric](18, 0) NULL
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[raw_json_payments_detail]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[raw_json_payments_detail](
	[id] [numeric](18, 0) IDENTITY(1,1) NOT NULL,
	[json_text] [text] NULL,
	[json_order] [text] NULL,
	[fecha] [datetime] NULL,
	[procesado] [varchar](1) NULL,
	[order_id] [varchar](50) NULL
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[raw_json_payments_detail_table]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[raw_json_payments_detail_table](
	[Element_ID] [numeric](18, 0) NULL,
	[SequenceNo] [numeric](18, 0) NULL,
	[Parent_ID] [numeric](18, 0) NULL,
	[Object_ID] [numeric](18, 0) NULL,
	[Name] [varchar](500) NULL,
	[StringValue] [varchar](500) NULL,
	[ValueType] [varchar](50) NULL,
	[id] [numeric](18, 0) NULL
) ON [PRIMARY]
GO
ALTER TABLE [dbo].[envios] ADD  DEFAULT (getdate()) FOR [fechaalt]
GO
ALTER TABLE [dbo].[ordenes_de_pedido] ADD  DEFAULT (getdate()) FOR [fechaalt]
GO
ALTER TABLE [dbo].[raw_json_orders] ADD  DEFAULT (getdate()) FOR [fecha]
GO
/****** Object:  StoredProcedure [dbo].[sp_envios]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create procedure [dbo].[sp_envios]
as
declare @cmdInsert varchar(5000)
declare @campo varchar(50)
declare @valores varchar(5000)
declare @element_id numeric
declare @values varchar(5000)
set nocount on
set @cmdInsert = 'insert into envios ('

Declare tabla cursor GLOBAL
        for select distinct '['+dbo.strzero(element_id,3)+ ltrim(rtrim(name))+']' from raw_json_payments_detail_table where name is not null order by 1
Open tabla

fetch tabla into @campo
while(@@fetch_status=0)
begin
  set @cmdInsert = @cmdInsert + @campo
   if @campo <>  '[155-]' begin
        set @cmdInsert = @cmdInsert + ','
   end
  fetch tabla into @campo
end
close tabla
deallocate tabla
 set @cmdInsert = @cmdInsert + ') values ('
-- campos
Declare valor cursor GLOBAL
        for select element_id, stringValue from raw_json_payments_detail_table where name is not null order by 1
Open valor
fetch valor into @element_id,@valores
Set @values = ''
while(@@fetch_status=0)
begin
    if @element_id = 1  begin
	   Set @values = ''
	end 
   set @values = @values + '''' + @valores +''''
    if @element_id<155  begin
	   Set @values = @values +','
	end 
    if @element_id=155  begin
	   Set @values = @values +')'
	   --select (@cmdInsert + @values)
	   exec (@cmdInsert + @values)
	end 

	
	
 
   
   fetch valor into @element_id,@valores
end
close valor
deallocate valor

GO
/****** Object:  StoredProcedure [dbo].[sp_fechadesde]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[sp_fechadesde]
as
declare @fecha datetime
declare @salida varchar(50)
set nocount on
-- El umbral fecha desde asi queda seteado una hora antes.
-- IMPORTANTE: Por definicion de ML no se tiene en cuenta minutos ni segundos
set @fecha= DATEADD([HOUR], -1, getdate())
--set @fecha='20201012'
set @salida = cast(year(@fecha) as varchar) +'-'
set @salida = @salida + case when month(@fecha) < 10 then '0' + cast(month(@fecha) as varchar) else cast(month(@fecha) as varchar) end
set @salida = @salida + '-'
set @salida = @salida + case when day(@fecha) < 10 then '0' + cast(day(@fecha) as varchar) else cast(day(@fecha) as varchar) end
set @salida = @salida +'T'
set @salida = @salida + case when datepart(hour,@fecha) < 10 then '0' + cast(datepart(hour,@fecha) as varchar) else cast(datepart(hour,@fecha) as varchar) end
set @salida = @salida +':00:00.000-00:00'
select @salida as resultado
GO
/****** Object:  StoredProcedure [dbo].[sp_fechahasta]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE procedure [dbo].[sp_fechahasta]
as
declare @fecha datetime
declare @salida varchar(50)
set nocount on
-- El umbral fecha hasta asi queda seteado una hora despues.
-- IMPORTANTE: Por definicion de ML no se tiene en cuenta minutos ni segundos (la hora despues es para eso)
set @fecha= DATEADD([HOUR], 1, getdate())
--set @fecha='20201013'
set  @salida = cast(year(@fecha) as varchar) +'-'
set @salida = @salida + case when month(@fecha) < 10 then '0' + cast(month(@fecha) as varchar) else cast(month(@fecha) as varchar) end
set @salida = @salida + '-'
set @salida = @salida + case when day(@fecha) < 10 then '0' + cast(day(@fecha) as varchar) else cast(day(@fecha) as varchar) end
set @salida = @salida +'T'
set @salida = @salida + case when datepart(hour,@fecha) < 10 then '0' + cast(datepart(hour,@fecha) as varchar) else cast(datepart(hour,@fecha) as varchar) end
set @salida = @salida +':00:00.000-00:00'
select @salida as resultado

GO
/****** Object:  StoredProcedure [dbo].[sp_getShipping_id]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE procedure [dbo].[sp_getShipping_id]
@id  varchar(200) = NULL
as
declare @cur_id varchar(200);

Set NOCOUNT ON
/*
primero con el orderid que traigo como parametro tengo que ir a buscar el id para caerle al shipping_id
*/
set @cur_id=(select max(id) from raw_json_orders_detail_table where stringvalue = @id and parent_id=13 and name='order_id')
--select @cur_id
select stringValue as shipping_id from raw_json_orders_detail_table where  parent_id=15  and id= @cur_id
GO
/****** Object:  StoredProcedure [dbo].[sp_nada]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
 CREATE procedure [dbo].[sp_nada]
 as
 -- no hacer nada para guardar los triggers
GO
/****** Object:  StoredProcedure [dbo].[sp_ordenes]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE procedure [dbo].[sp_ordenes]
as
declare @cmdInsert varchar(5000)
declare @campo varchar(50)
declare @valores varchar(5000)
declare @element_id numeric
declare @values varchar(5000)
set nocount on
set @cmdInsert = 'insert into ordenes_de_pedido ('

Declare tabla cursor GLOBAL
        for select distinct '['+dbo.strzero(element_id,3)+ ltrim(rtrim(name))+']' from raw_json_orders_detail_table where name is not null order by 1
Open tabla

fetch tabla into @campo
while(@@fetch_status=0)
begin
  set @cmdInsert = @cmdInsert + @campo
   if @campo <>  '[117-]' begin
        set @cmdInsert = @cmdInsert + ','
   end
  fetch tabla into @campo
end
close tabla
deallocate tabla
 set @cmdInsert = @cmdInsert + ') values ('
-- campos
Declare valor cursor GLOBAL
        for select element_id, stringValue from raw_json_orders_detail_table where name is not null order by 1
Open valor
fetch valor into @element_id,@valores
Set @values = ''
while(@@fetch_status=0)
begin
    if @element_id = 1  begin
	   Set @values = ''
	end 
   set @values = @values + '''' + @valores +''''
    if @element_id<117  begin
	   Set @values = @values +','
	end 
    if @element_id=117  begin
	   Set @values = @values +')'
	   --select (@cmdInsert + @values)
	   exec (@cmdInsert + @values)
	end 

	
	
 
   
   fetch valor into @element_id,@valores
end
close valor
deallocate valor

GO
/****** Object:  StoredProcedure [dbo].[sp_raw_json_orders]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE procedure [dbo].[sp_raw_json_orders]
 as
 set nocount on
 declare @json nvarchar(max); 
 declare @id numeric;

Declare raw_json cursor GLOBAL
        for Select id, json_text from raw_json_orders where procesado is null
Open raw_json

fetch raw_json into @id, @json
while(@@fetch_status=0)
begin
    insert into raw_json_orders_table(Element_ID, SequenceNo, Parent_ID, Object_ID, name, StringValue, ValueType)
                Select Element_ID, SequenceNo, Parent_ID, Object_ID, name, StringValue, ValueType from parseJSON(@json)
	update raw_json_orders_table set id = @id where id  is  null

    fetch raw_json into @id, @json
end
update raw_json_orders set procesado ='S' where procesado is null
close raw_json
deallocate raw_json
GO
/****** Object:  StoredProcedure [dbo].[sp_raw_json_orders_detail]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE procedure [dbo].[sp_raw_json_orders_detail]
 as
 set nocount on
 declare @json nvarchar(max); 
 declare @id numeric;

Declare raw_json_cursor cursor GLOBAL
        for Select id, json_text from raw_json_orders_detail where procesado is null
Open raw_json_cursor

fetch raw_json_cursor into @id, @json
while(@@fetch_status=0)
begin
    insert into raw_json_orders_detail_table(Element_ID, SequenceNo, Parent_ID, Object_ID, name, StringValue, ValueType)
                Select Element_ID, SequenceNo, Parent_ID, Object_ID, name, StringValue, ValueType from parseJSON(@json)
	update raw_json_orders_detail_table set id = @id where id  is  null

    fetch raw_json_cursor into @id, @json
end
update raw_json_orders_detail set procesado ='S' where procesado is null
close raw_json_cursor
deallocate raw_json_cursor
--exec sp_ordenes

GO
/****** Object:  StoredProcedure [dbo].[sp_raw_json_payments_detail]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[sp_raw_json_payments_detail]
 as
 set nocount on
 declare @json nvarchar(max); 
 declare @id numeric;

Declare raw_json cursor GLOBAL
        for Select id, json_text from raw_json_payments_detail where procesado is null
Open raw_json

fetch raw_json into @id, @json
while(@@fetch_status=0)
begin
    insert into raw_json_payments_detail_table(Element_ID, SequenceNo, Parent_ID, Object_ID, name, StringValue, ValueType)
                Select Element_ID, SequenceNo, Parent_ID, Object_ID, name, StringValue, ValueType from parseJSON(@json)
	update raw_json_payments_detail_table set id = @id where id  is  null

    fetch raw_json into @id, @json
end
update raw_json_payments_detail set procesado ='S' where procesado is null
close raw_json
deallocate raw_json
--exec sp_envios

GO
/****** Object:  StoredProcedure [dbo].[sp_ultimas_ordenes]    Script Date: 13/10/2020 11:34:48 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE procedure [dbo].[sp_ultimas_ordenes]
as
declare @max_order numeric
set nocount on
set @max_order = (select max(id) from raw_json_orders_table)
select stringValue as order_id from  raw_json_orders_table where name='order_id' and id= @max_order order by 1

GO
