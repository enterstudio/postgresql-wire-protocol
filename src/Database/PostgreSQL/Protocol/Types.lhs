> -- | Module:    Database.PostgreSQL.Protocol.Types
> -- Description: Protocol data types
> -- Copyright:   (c) 2015 Patryk Zadarnowski <pat@jantar.org>
> -- License:     BSD3
> -- Maintainer:  pat@jantar.org
> -- Stability:   experimental
> -- Portability: portable
> --
> -- This module defines the format of all messages exchanged between a PostgreSQL backend (i.e., server)
> -- and frontend (i.e., client.)
> --
> -- At this level of abstraction, we try to restrict decoding of messages to their outermost structure,
> -- retaining most message fields in their original binary encoding, usually directly as fixed-width
> -- numeric types from "Data.Int" and "Data.Word". Variable-width field types are represented by
> -- strict byte strings when the field tends to be atomic in nature (e.g., names) or lazy byte
> -- strings for fields that exibit further internal structure likely to require further decoding
> -- in higher layers (e.g., query strings and table cell values.) Message fields that represent
> -- vectors or lists of quantities are represented by arrays (unboxed when possible) with 16-bit
> -- unsigned index types to reduce the amount of memory allocations.

> {-# LANGUAGE PatternSynonyms, ScopedTypeVariables #-}

> module Database.PostgreSQL.Protocol.Types (
>   -- * Array Fields
>   --
>   -- | For compactness, we depict those as Haskell arrays (unboxed when possible) with
>   --   a 16-bit index type. PostgreSQL documentation is not clear on whether array sizes
>   --   should be interpreted as a signed or unsigned number by the server), but fortunately
>   --   this doesn't really matter in practice, since other implementation considerations
>   --   restrict the result sets to far smaller number of columns. The official upper bound
>   --   is 1600, although current implementations are capable of accomodating up to 1736
>   --   columns in query results. In our implementation, we treat array indexes as signed
>   --   but reject all arrays with sizes greater than 32767 as invalid.
>   Array16, UArray16,
>   -- * Message Types
>   SessionMessage (..),
>    currentMajorVersion,
>    currentMinorVersion,
>   SSLResponse (..),
>   FrontendMessage (..),
>   BackendMessage (..),
>   -- * Frontend Authentication
>   AuthenticationResponse (..),
>   -- * Transaction Status Codes
>   TransactionStatus,
>    pattern TransactionIdle,
>    pattern TransactionInProgress,
>    pattern TransactionFailed,
>   -- * Data Values
>   Value,
>   -- * Data Transmission Formats
>   Format,
>    pattern TextFormat,
>    pattern BinaryFormat,
>   StreamFormat,
>    pattern TextStreamFormat,
>    pattern BinaryStreamFormat,
>   -- * Session Objects
>   SessionObjectKind,
>    pattern StatementObject,
>    pattern PortalObject,
>   SessionObjectName,
>   PortalName,
>   StatementName,
>   -- * Field Descriptions
>   FieldDescription (..),
>   -- * Notice Fields
>   --
>   -- | When issuing a notice or an error response, a backend may describe
>   --   various aspects of the underlying condition through a series of
>   --   /notice fields/, each tagged with a byte describing the field's
>   --   semantics, such as severity of the condition, associated database
>   --   object or a human-readable error message.
>   --
>   --   The 'NoticeSeverity', 'NoticeCode' and 'NoticeMessage' fields
>   --   must always be present in every notice and error response message,
>   --   but all other tags may be included or omitted freely at the backend's
>   --   discretion. A given tag may appear at most once in a single notice.
>   --
>   --   The client is responsible for formatting displayed information to meet its needs;
>   --   in particular it should break long lines as needed. Newline characters appearing
>   --   in the error message fields should be treated as paragraph breaks, not line breaks.
>   --
>   --   __Note:__ The 'NoticeSchema', 'NoticeTable', 'NoticeColumn', 'NoticeDataType' and 'NoticeConstraint' fields
>   --   are supplied only for a liminted number of error types and frontends should not assume that the presence
>   --   of any of these fields guarantees the presence of another field. Core error sources observe the interrelationships
>   --   noted below, but user-defined functions may use these fields in other ways. In the same vein, frontends should not
>   --   assume that these fields denote contemporary objects in the current database.
>   NoticeFields,
>   NoticeField,
>   NoticeFieldTag,
>    pattern NoticeSeverity,
>    pattern NoticeCode,
>    pattern NoticeMessage,
>    pattern NoticeDetail,
>    pattern NoticeHint,
>    pattern NoticePosition,
>    pattern NoticeInternalPosition,
>    pattern NoticeInternalQuery,
>    pattern NoticeContext,
>    pattern NoticeSchema,
>    pattern NoticeTable,
>    pattern NoticeColumn,
>    pattern NoticeDataType,
>    pattern NoticeConstraint,
>    pattern NoticeFile,
>    pattern NoticeLine,
>    pattern NoticeRoutine,
>   -- * Miscellaneous Types
>   ChannelName,
>   ColumnID,
>   DataString,
>   FieldName,
>   ObjectID,
>   ParameterName,
>   ProcessID,
>   QueryString,
>   ResultTag,
>   ValueString,
> ) where

> import Data.Array
> import Data.Array.Unboxed
> import Data.ByteString (ByteString)
> import Data.Int
> import Data.Word

> import qualified Data.ByteString.Lazy as Lazy


  Array Fields
  ============

> -- | Type used to represent arrays of unboxed (numeric) values in PostgreSQL messages.
> type UArray16 a = UArray Int16 a

> -- | Type used to represent arrays of boxed (variable-length) values in PostgreSQL messages.
> type Array16 a = Array Int16 a


  Communication Message Types
  ===========================

> -- | The type of the three session startup messages sent by a PostgreSQL frontend to the backend
> --   to initiate a new database connection. These messages use an encoding incompatible with all
> --   other message types, and must therefore only ever appear as the very first  message posted
> --   on a new socket connection to the backend.
> data SessionMessage =

>   -- | A message of the form “@StartupMessage m n ps@” requests initiation of a new database
>   --   connection using protocol version @m.n@, optionally configuring some session parameters
>   --   to the specified default values. Besides the usual set of server configuration parameters
>   --   that can be configured at runtime using the SQL @SET@ command, 'StartupMessage' accepts
>   --   the following three session-specific parameters:
>   --
>   --   * @user@, the database user name used to use,
>   --   * @database@, the target database, and
>   --   * @options@, command-line arguments for the backend.
>   --
>   --   The @user@ parameter is mandatory, but the other two may be omitted, defaulting to
>   --   a database with the same name as the @user@ and an empty set of command-line arguments.
>   --   In addition, the use of @options@ parameter has been deprecated in favour of setting
>   --   individual run-time parameters.
>   --
>   --   The major and minor protocol version should be always set to 'currentMajorVersion'
>   --   and 'currentMinorVersion', respectively, since PostgreSQL does not maintain backward
>   --   compatiblity between releases of its protocol, and the current version (3.0) is the
>   --   only version guaranteed to be supported by this library.
>   StartupMessage Word16 Word16 [(ParameterName, ValueString)] |

>   -- | A message of the form “@CancelRequest pid secret@” requests cancellation of a query
>   --   currently being executed on the server by another backend process with the process
>   --   ID @pid@. In order to demonstrate authority to interact with this backend process,
>   --   the frontend must include in the message the unique 32-bit key @secret@ generated
>   --   by the backend process and supplied to the frontend in a 'BackendKeyData' message
>   --   sent as part of the session establishment protocol of the targeted communication session.
>   CancelRequest !ProcessID !Word32 |

>   -- | Requests establishment of an SSL-protected communication session.
>   --   The server should respond with an 'SSLResponse' message described below.
>   SSLRequest
>   deriving (Eq, Ord, Show)

> -- | Current major version of the PostgreSQL wire protocol, to be used in 'StartupMessage'.
> --   Version number 1234 and higher are reserved for special connection headers such
> --   as 'CancelRequest' and 'SSLRequest', so actual major version numbers in 'StartupMessage'
> --   must be equal to 1233 or lower. The current version 3.0 has been introduced in
> --   PostgreSQL 7.4 and is the only version supported by this library. The previous
> --   version 2.0, introduced in PostgreSQL 6.4, is incompatible with version 3.0, and
> --   I was unable to find documentation for the original version 1.0 of the protocol.
> currentMajorVersion :: Word16
> currentMajorVersion = 3

> -- | Current minor version of the PostgreSQL wire protocol, set to 0 in all versions of
> --   the PostgreSQL frontend/backend protocol released so far.
> currentMinorVersion :: Word16
> currentMinorVersion = 0

> -- | The type of a special-case response to an 'SSLRequest' message described above.
> data SSLResponse =

>   -- | Indicates to the frontend that the backend has accepted the 'SSLRequest'. The frontend
>   --   should perform a standard SSL startup handshake as per SSL Specification and, if successful,
>   --   proceed to send the usual 'StartupMessage' or 'CancelRequest' over the newly-established
>   --   SSL channel.
>   SSLRequestAccepted |

>   -- | Indicates to the frontend that the backend has rejected the 'SSLRequest'. The frontend
>   --   has an option of abandoning the connection by closing the underlying socket, or proceeding
>   --   with an unencrypted session by sending the usual 'StartupMessage' or 'CancelRequest' over
>   --   the same socket without encryption.
>   SSLRequestRejected |

>   -- | Indicates to the frontend that the backend does not understand 'SSLRequest' messages.
>   --   This would only occur if the server predates the addition of SSL support to PostgreSQL.
>   --   Such servers are now very ancient, and likely do not exist in the wild anymore. In this
>   --   case the connection must be closed, but the frontend might choose to open another, fresh
>   --   connection and proceed without requesting SSL. The notice returned by the backend is
>   --   unlikely to continue meaningful error information and should most likely be ignored.
>   SSLRequestFailed NoticeFields
>   deriving (Eq, Ord, Show)

> -- | The type of messages sent by frontend to a PostgreSQL backend or server.
> --   These are the messages tagged with ‘@F@’ in Chapter 49 of PostgreSQL documentation,
> --   with exception of the @CancelRequest@, @StartupMessage@ and @SSLRequest@ message types
> --   that are defined separately as 'SessionMessage' values.
> data FrontendMessage =

>   -- | A message of the form “@Bind p s pfs pvs rfs@” message requests /binding/ (i.e., creation)
>   --   of a new portal @p@ to an existing parsed statement @s@, with parameter formats @pfs@,
>   --   parameter values @pvs@ and result formats @rfs@. The default /unnamed portal/ and/or
>   --   /unnamed statement/ can be selected by setting @p@ and/or @s@ to an empty byte string
>   --   ('ByteString.null').
>   --
>   --   The @pvs@ array must provide a field value (possibly 'Nothing' for SQL @NULL@) for
>   --   every actual parameter mentioned in the SQL command @s@ using the @?@ or @$/n/@ syntax.
>   --   Each of these values can be encoded in either the default textual or binary transfer
>   --   format (both are represented in @Value@ as simple byte strings) and the actual
>   --   choice of the format is determined by the @pfs@ array. The @pfs@ array can be empty
>   --   (indicating that all parameters are encoded using the default textual format),
>   --   singleton (indicating that all parameters are encoded using the same explicitely
>   --   specified format) or else must have the same length as the @pvs@ array, specifying
>   --   the transfer formats individually for each parameter value.
>   --
>   --   Likewise, the @rfs@ array, which determines the transfer formats expected by the
>   --   frontend for any result values returned by the backend, can be left empty, requesting
>   --   the backend to use the default textual encoding of all result values), specified
>   --   as a singleton array (requesting the same encoding for all result fields), or
>   --   else match the number of columns in the result set, thus specifying an individual
>   --   format for each column.
>   Bind PortalName StatementName (UArray16 Format) (Array16 Value) (UArray16 Format) |

>   -- | A message of the form “@Close k x@” requests that the session object @x@ of type @k@
>   --   (either a 'StatementObject' created by the 'Parse' message or a 'PortalObject' created
>   --   with 'Bind') is no longer required, and that its underlying resources should be released
>   --   by the server for other uses.
>   Close SessionObjectKind SessionObjectName |

>   -- | Transmits a chunk of a @COPY@ data string from the frontend to the backend.
>   --   The actual format of the stream data is determined by the user as part of the
>   --   requesting @COPY@ command and communicated by the backend back to the frontend
>   --   in the 'CopyInResponse', 'CopyOutResponse' or 'CopyBothResponse' message that
>   --   heralds commencement of the @COPY@ subprotocol session.
>   --
>   --   By convention, backends are expected to send complete data rows in a 'CopyOutData'
>   --   message, but frontends are allowed to divide stream data into chunks arbitriarly
>   --   without regard of data row boundaries.
>   CopyInData DataString |

>   -- | Sent after the final 'CopyInData' message of a given @COPY@ subprotocol session,
>   --   indicates successful completion of an entire @COPY@ data stream.
>   CopyInDone |

>   -- | A message of the form “@CopyFail msg@” should be sent by the frontend to indicate
>   --   inability to supply the required @COPY@ data stream. The byte string @msg@ should
>   --   provide a human-readable description of the exact error condition behind the failure.
>   CopyFail ValueString |

>   -- | A message of the form “@Describe k x@” requests that the backend provide details about
>   --   the session object @x@ of type @k@ (either a 'StatementObject' created by the 'Parse'
>   --   message or a 'PortalObject' created with 'Bind'.) The backend should respond with
>   --   a 'ParameterDescription' or 'RowDescription' message for statement and portal objects,
>   --   respectively.
>   Describe SessionObjectKind SessionObjectName |

>   -- | A message of the form “@Execute p n@” requests execution of a bound portal @p@.
>   --   If @n@ is greater than zero and @p@ represents an SQL query, at most @n@ data rows
>   --   should be returned by the backend; otherwise, the @n@ parameter is ignored and all data
>   --   rows should be returned. If @p@ returns a row set and @n@ is negative, the results are
>   --   left unspecified by the protocol.
>   Execute PortalName !Int32 |

>   -- | Indicates that the backend should immediately return any pending command result data.
>   Flush |

>   -- | A message of the form “@FunctionCall oid afs avs rf@” requests execution of
>   --   a PostgreSQL function with the given object ID @oid@, supplying it an array of
>   --   argument values @avs@ encoded in the transfer format specified by the array @afs@,
>   --   and expecting the function's sole result value to be encoded using the transfer
>   --   format @rf@. As for 'Bind' messages, @afs@ can be an empty array if all argument
>   --   values are supplied in the default text format, a singleton array to specify the
>   --   same explicit transfer format for all arguments, or else it must specify precisely
>   --   one format for each of the argument values in @avs@.
>   FunctionCall !ObjectID (UArray16 Format) (Array16 Value) !Format |

>   -- | A message of the form “@Parse s q pts@” requests creation of a new prepared statement
>   --   object with the name @s@ in the current session from the SQL command @q@.
>   --   The statement name can be set to 'ByteString.null' to create the default unnamed
>   --   statement. The array @pts@ specifies object IDs of PostgreSQL types for any query
>   --   parameters appearing in @q@. It is not required to specify types for all query
>   --   parameters and may even be left empty if not required; the types of any parameters
>   --   omitted from @pts@ are then inferred directly from the query string @q@ itself.
>   Parse StatementName QueryString (UArray16 ObjectID) |

>   -- | Supplies a password string in response to an 'Authentication' message from the
>   --   backend, encrypted if required using the method requested by the backend.
>   PasswordMessage ValueString |

>   -- | A message of the form “@Query q@” requests a streamlined processing of the SQL
>   --   command @q@, which should be parsed, bound, executed and eventually closed by
>   --   the backend without further intervention by the frontend. The backend is allowed
>   --   to implement this interface using the default unnamed session statement and portal,
>   --   thus overwriting any such statements created in the current session explicitly.
>   Query QueryString |

>   -- | Requests synchronisation point after a failed query in the backend.
>   --   After receiving a “@Sync@” message, the backend should exit error recovery
>   --   mode and prepare itself to receive the next valid query from the frontend.
>   Sync |

>   -- | Requests graceful termination of a communication session. After transmitting
>   --   a “@Terminate@” message, the frontend should refrain from sending any further
>   --   messages to the backend and immediately close the connection socket.
>   Terminate
>   deriving (Eq, Ord, Show)

> -- | The type of messages sent by backend to a PostgreSQL frontend or client.
> --   These are the messages tagged with ‘@B@’ in Chapter 49 of PostgreSQL documentation.
> data BackendMessage =

>   -- | Sent by a backend in response to a 'StartupMessage' with details of any
>   --   authentication requirements imposed on the frontend. In Chapter 49 of
>   --   PostgreSQL manual, this is documented as an array of individual messages,
>   --   but in the Haskell implementation we combine them into a single
>   --   'AuthenticationResponse' constructor to simplify processing.
>   AuthenticationResponse AuthenticationResponse |

>   -- | A message of the form “@BackendKeyData pid k@” is sent by the backend
>   --   as part of the session establishment protocol, providing the frontend
>   --   process with the backend process ID @pid@ and secret @k@ required of
>   --   the frontend to issue query cancellation requests (see: 'CancelQuery'
>   --   message type above.)
>   BackendKeyData !ProcessID !Word32 |

>   -- | Sent by the backend to indicate successful completion of a 'Bind' request.
>   BindComplete |

>   -- | Sent by the backend to indicate successful completion of a 'Close' request.
>   CloseComplete |

>   -- | Sent by the backend to indicate successful completion of a 'Query' or 'Execute'
>   --   request, after any query results have been returned through an appropriate
>   --   number of 'DataRow' messages.
>   CommandComplete ResultTag |

>   -- | Transmits a chunk of a @COPY@ data string from the backend to the frontend.
>   --   The actual format of the stream data is determined by the user as part of the
>   --   requesting @COPY@ command and communicated by the backend back to the frontend
>   --   in the 'CopyInResponse', 'CopyOutResponse' or 'CopyBothResponse' message that
>   --   heralds commencement of the @COPY@ subprotocol session.
>   --
>   --   By convention, backends are expected to send complete data rows in a 'CopyOutData'
>   --   message, but frontends are allowed to divide stream data into chunks arbitriarly
>   --   without regard of data row boundaries.
>   CopyOutData DataString |

>   -- | Sent after the final 'CopyOutData' message of a given @COPY@ subprotocol session,
>   --   indicates successful completion of an entire @COPY@ data stream.
>   CopyOutDone |

>   -- | A message of the form “@CopyInResponse f fs@” is sent by the backend to initiate
>   --   an inbound @COPY@ subprotocol session with the frontend. The frontend should
>   --   respond with zero or more 'CopyInData' messages followed by a 'CopyInDone',
>   --   or, if it is not prepared to do so, send a 'CopyFail' message back to the server.
>   --
>   --   The /stream format/ parameter @f@ defines the overall format of the data stream
>   --   requested by the backend, while the array @fs@ defines the transfer formats of
>   --   the individual data fields in each row, and must always be set to 'TextFormat'
>   --   if the overal format of the stream @f@ is set to 'TextStreamFormat'.
>   CopyInResponse StreamFormat (UArray16 Format) |

>   -- | A message of the form “@CopyOutResponse f fs@” is sent by the backend to initiate
>   --   an outbound @COPY@ subprotocol session with the frontend. It should be followed
>   --   immediately by zero or more 'CopyOutData' messages and completed with 'CopyOutDone'.
>   --
>   --   The /stream format/ parameter @f@ defines the overall format of the data stream
>   --   requested by the backend, while the array @fs@ defines the transfer formats of
>   --   the individual data fields in each row, and must always be set to 'TextFormat'
>   --   if the overal format of the stream @f@ is set to 'TextStreamFormat'.
>   CopyOutResponse StreamFormat (UArray16 Format) |

>   -- | A message of the form “@CopyOutResponse f fs@” is sent by the backend to initiate
>   --   a bidirectional @COPY@ subprotocol session, used only for streaming replication.
>   --
>   --   The /stream format/ parameter @f@ defines the overall format of the data stream
>   --   requested by the backend, while the array @fs@ defines the transfer formats of
>   --   the individual data fields in each row, and must always be set to 'TextFormat'
>   --   if the overal format of the stream @f@ is set to 'TextStreamFormat'.
>   CopyBothResponse StreamFormat (UArray16 Format) |

>   -- | Sent by the backend with a list of column or field values returned from a data set
>   --   returning SQL query such as @SELECT@ or @FETCH@.
>   DataRow (Array16 Value) |

>   -- | Sent by the backend in lieu of the 'CommandComplete' message as a response to
>   --   an attempt to execute an empty query string.
>   EmptyQueryResponse |

>   -- | Sent by the backend to indicate an error condition, with details of the error
>   --   communicated through a list of tagged /notice fields/ as described in the
>   --   definition of the 'NoticeFieldTag'.
>   ErrorResponse NoticeFields |

>   -- | Sent by the backend to indicate successful completion of a 'FunctionCall'
>   --   operation, with the sole value returned by the function call (possibly @NULL@.)
>   FunctionCallResponse Value |

>   -- | Sent by the backend in lieu of the 'RowDescription' message, in response
>   --   to a 'Describe' message for a statement or portal which represents an SQL
>   --   command such as @CREATE@ or @INSERT@ that does not return a row set.
>   NoData |

>   -- | Sent by the backend to inform the frontend of a condition such as a warning
>   --   or administrator action that may, or may be relevant to an operation currently
>   --   in progress and may be issued asynchronously to any other message exchanges.
>   --   Frontends must be prepared to accept such messages from the backend at any
>   --   time after the initial 'StartupMessage' of a communication session.
>   NoticeResponse NoticeFields |

>   -- | A message of the form “@NotificationResponse pid c x@” is sent by the backend
>   --   to inform the frontend of a @NOTIFY@ event issued by the backend process @pid@,
>   --   on the channel @c@ with a payload @x@. Frontends must be prepared to accept
>   --   such messages from the backend at any time after the initial 'StartupMessage'
>   --   of a communication session, irrespective of any other message exchanges being
>   --   conducted.
>   NotificationResponse !ProcessID ChannelName ValueString |

>   -- | Sent by the backend in response to a statement variant of a 'Describe' message,
>   --   with object IDs of the types of all parameters required by the statement.
>   ParameterDescription (UArray16 ObjectID) |

>   -- | A message of the form “@ParameterStatus p x@” is sent by the backend whenever
>   --   of the “significant” session parameters is changed, either explicitly by the
>   --   user with the SQL @SET@ comand, or as a result of administrator action.
>   --   Frontends must be prepared to accept such messages from the backend at any
>   --   time after the initial 'StartupMessage' of a communication session,
>   --   irrespective of any other message exchanges being conducted.
>   --
>   --   What constitutes a “significant” message is currently left unspecified in
>   --   PostgreSQL documentation, and may even become configurable in future server
>   --   versions. At present time, these messages are issued for changes of the
>   --   following parametes: @server_version@, @server_encoding@, @client_encoding@,
>   --   @application_name@, @is_superuser@, @session_authorization@, @DateStyle@,
>   --   @IntervalStyle@, @TimeZone@, @integer_datetimes@ and @standard_conforming_strings@.
>   ParameterStatus ParameterName ValueString |

>   -- | Sent by the backend in response to a successful completion of a 'Parse' operation.
>   ParseComplete |

>   -- | Sent by the backend after the maximum number of 'DataRow' messages requested by
>   --   an 'Execute' operation has been reached without exhausting the entire result set.
>   PortalSuspended |

>   -- | Sent by the backend as a synchronization point, indicating readiness to process
>   --   a new SQL command, carrying with it the status of the current transaction (if any.)
>   ReadyForQuery !TransactionStatus |

>   -- | Sent by the backend at the beginning of a result set as part of a simple or extended
>   --   query protocol, or in response to a 'Describe' message referring to an SQL command
>   --   that returns a row set.
>   RowDescription (Array16 FieldDescription)
>   deriving (Eq, Ord, Show)


> -- | Details of a backend response to a frontend's authentication request
> --   depicted by a session's 'StartupMessage'.
> data AuthenticationResponse =

>   -- | Issued by the backend to signify successful authentication of the frontend's credentials.
>   AuthenticationOk |

>   -- | Issued by the backend to initiate Kerberos V5 authentication dialogue,
>   --   described separately in Kerberos specification. This authentication method
>   --   is no longer supported by recent versions of PostgreSQL software.
>   AuthenticationKerberosV5 |

>   -- | Issued by the backend to request clear-text password authentication.
>   --   The frontend should respond with a 'PasswordMessage' containing an unencrypted
>   --   text of the user's password.
>   AuthenticationCleartextPassword |

>   -- | A message of the form “@AuthenticationMD5Password s@” is issued by the backend
>   --   to request MD5-based password authentication with the specified 32-bit /salt/ @s@.
>   --   The frontend should respond with a 'PasswordMessage x', in which @x@ is a byte string
>   --   derived from the user's login name @u@, password @p@ and the supplied salt @ss@ as follows:
>   --
>   -- @
>   --      "md5" <> md5 (md5 (/p/ <> /u/) <> /ss/
>   -- @
>   --
>   --   where /s/ is a 4-byte byte string obtained from the big-endian encoding of the supplied
>   --   salt @s@, and @md5(x)@ is a function that returns a 32-byte bytestring obtained from the
>   --   lowercase hexadecimal encoding of the MD5 signature of @x@.
>   AuthenticationMD5Password !Word32 |

>   -- | Issued by the backend to request SCM credential authentication, possible only on
>   --   connections over local Unix-domain sockets on platforms that support SCM credential
>   --   messages. The frontend must issue an SCM credential message and then send a single
>   --   data byte. The contents of the data byte are uninteresting; it's only used to ensure
>   --   that the server waits long enough to receive the credential message. If the credential
>   --   is acceptable, the server responds with an 'AuthenticationOk', otherwise it responds
>   --   with an 'ErrorResponse'. This message type is only issued by versions of PostgreSQL
>   --   servers earlier than 9.1 and may eventually be removed from the protocol specification.
>   AuthenticationSCMCredential |

>   -- | Issued by the backend to request GSS credential authentication. The frontend should respond
>   --   by initiating a GSSAPI negotiation, sending a 'PasswordMessage' with the first part of the
>   --   GSSAPI data stream. If further messages are needed, the server will respond with an
>   --   'AuthenticationGSSContinue' message.
>   AuthenticationGSS |

>   -- | Issued by the backend to request SSPI credential authentication. The frontend should respond
>   --   by initiating a SSPI negotiation, sending a 'PasswordMessage' with the first part of the
>   --   SSPI data stream. If further messages are needed, the server will respond with an
>   --   'AuthenticationGSSContinue' message.
>   AuthenticationSSPI |

>   -- | Issued by the backend as a response to the previous step of GSSAPI or SSPI negotiation,
>   --   i.e., an 'AuthenticationGSS', 'AuthenticationSSPI' or an earlier 'AuthenticationGSSContinue'
>   --   message. If the GSSAPI or SSPI data in this message indicates more data is needed to complete
>   --   the authentication, the frontend must send that data as another 'PasswordMessage'.
>   --   If GSSAPI or SSPI authentication is completed by this message, the server will eventually
>   --   send 'AuthenticationOk' to indicate successful authentication or 'ErrorResponse' to indicate
>   --   failure.
>   AuthenticationGSSContinue DataString |

>   -- | A message of the form “@AuthenticationMiscellaneous t x@” is used to encode possible future
>   --   authentication methods that are not recognized by the current version of the library.
>   --   The 32-bit tag @t@ describes the authentication method requested and @x@ described any
>   --   authentication parameters (possibly 'Data.ByteString.Lazy.null'), in the method-specific
>   --   format. The only sensible response to this message is to abandon the conection after
>   --   issuing an appropriate notification message to the user.
>   AuthenticationMiscellaneous Word32 DataString
>   deriving (Eq, Ord, Show)


  Transaction Status Codes
  ========================

> -- | Transaction status codes returned in 'ReadyForQuery' messages.
> type TransactionStatus = Word8

> -- | (‘@I@’) Transaction status code returned to indicate that the backend process is “idle”, i.e., outside of a transaction block.
> pattern TransactionIdle = 0x49 :: TransactionStatus -- 'I'

> -- | (‘@T@’) Transaction status code returned to indicate that the backend process is currently operating within a transaction block.
> pattern TransactionInProgress = 0x54 :: TransactionStatus -- 'T'

> -- | (‘@E@’) Transaction status code returned to indicate that the backend process is currently operating in a “transaction recovery” mode
> --   after encoutering an error within a transaction block. All further SQL requests will be rejected until the block is completed with
> --   an SQL @ROLLBACK@ command.
> pattern TransactionFailed = 0x45 :: TransactionStatus -- 'E'


  Data Values
  ===========

> -- | Data values supplied as parameters to SQL commands and returned back from the
> --   server as query result elements are represented by optional lazy bytestrings,
> --   with @NULL@ depicated as 'Nothing'.
> type Value = Maybe DataString


  Data Transmission Formats
  =========================

> -- | Haskell type used to describe encoding formats of query parameters and result
> --   data values. At the moment, PostgreSQL defines two: the default text format
> --   'TextFormat' (@0@) and the somewhat poorly-documented binary format
> --   'BinaryFormat (@1@).
> type Format = Word16

> -- | (@0@) Data exchanged in the default SQL text format similar to that defined by
> --   SQL for string constants, but without the surrounding quotes or quote escaping.
> pattern TextFormat = 0 :: Format

> -- | (@1@) Data exchanged in the somewhat underdocumented PostgreSQL binary format.
> --   This should probably be only used for a handful of simple types such as
> --   fixed-width integers that have a well-documented binary format, and types
> --   such as timestamps and floating point numbers for which the use of text
> --   format could result in loss of precision. Details of the known binary
> --   formats are described separately in "Database.PostgreSQL.Protocol.Binary".
> pattern BinaryFormat = 1 :: Format

> -- | Haskell type used to describe encoding format of data streams exchanged using
> --   the @COPY@ subprotocol. At the moment, PostgreSQL defines two: the default
> --   'TextStreamFormat' (@0@) and a more compact 'BinaryStreamFormat' (@1@).
> type StreamFormat = Word8

> -- | (@0@) Data streamed in the default text format, in which rows are separated
> --   by newlines and columns are separated by the delimiter character configured
> --   as part of the @COPY@ command.
> pattern TextStreamFormat = 0 :: StreamFormat

> -- | (@1@) Data streamed in a compact binary format described in the PostgreSQL
> --   documentation of the @COPY@ command.
> pattern BinaryStreamFormat = 1 :: StreamFormat


  Session Objects
  ===============

> -- | A type used to select the exact namespace of session object names in
> --   'Close' and 'Describe' messages; must be either 'StatementObject' or
> --   'PortalObject'.
> type SessionObjectKind = Word8

> -- | (‘@S@’) The corresponding 'SessionObjectName' refers to a prepared statement.
> pattern StatementObject = 0x53 :: SessionObjectKind -- 'S'

> -- | (‘@P@’) The corresponding 'SessionObjectName' refers to a bound portal.
> pattern PortalObject = 0x50 :: SessionObjectKind -- 'P'

> -- | All session objects are identified by strict byte strings, with a separate
> --   namespace used for each session object kind.
> type SessionObjectName = ByteString

> -- | A 'SessionObjectName' used to identify a statement.
> type StatementName = ByteString

> -- | A 'SessionObjectName' used to identify a portal.
> type PortalName = ByteString


  Field Descriptions
  ==================

> -- | A data type used to describe a single result field in a 'RowDescription' message.
> --   Each field description value has the form @FieldDescription /x/ /tid/ /
> data FieldDescription = FieldDescription {
>   fieldName               :: FieldName,   -- ^ The field's name.
>   fieldTableID            :: !ObjectID,   -- ^ If the field can be identified as a column of a specific table, the object ID of the table;
>                                           --   otherwise 'Database.PostgreSQL.Protocol.ObjectIDs.NULL'
>   fieldColumnID           :: !ColumnID,   -- ^ If the field can be identified as a column of a specific table, the attribute number of the column; otherwise zero.
>   fieldDataTypeID         :: !ObjectID,   -- ^ The object ID of the field's data type.
>   fieldDataTypeSize       :: !Int16,      -- ^ The data type size, negative for fields of a variable-width type.
>   fieldDataTypeModifier   :: !Word32,     -- ^ The type modifier, with semantics defined individually for each data type.
>   fieldFormat             :: !Format      -- ^ The format code used by the field; in a 'RowDescription' message returned from the statement variant of 'Describe',
>                                           --   the format code is not yet known and will always be set to the default value of 'TextFormat'.
> } deriving (Eq, Ord, Show)


  Notice Fields
  =============

> -- | A type used to depict a list of notice fields, collectively describing
> --   all known aspects of an error condition or notice message.
> type NoticeFields = [NoticeField]

> -- | A type used to depict a single notice field as a pair @(t, x)@,
> --   describing one particular aspect of an error condition or notice message,
> --   as identified by the /tag/ @t@. The precise semantics of the associated
> --   field value @x@ are described individually below for each known tag byte.
> type NoticeField = (NoticeFieldTag, ValueString)

> -- | Tags describing semantics of individual fields within a notice or error response.
> type NoticeFieldTag = Word8

> -- | (‘@S@’) Indicates that the field describes severity of the condition.
> --   The field itself must be set to one of @ERROR@, @FATAL@ or @PANIC@ for 'ErrorResponse' messages,
> --   or @WARNING@, @NOTICE@, @DEBUG@, @INFO@, or @LOG@ in a notice message.
> --   It may also be set to localized translation of one of these.
> --   This field must always be present in every notice and error message.
> pattern NoticeSeverity = 0x53 :: NoticeFieldTag -- 'S'

> -- | (‘@C@’) Indicates that the field describes the SQLSTATE code for the error.
> --   These codes are not localizable and the field must be present in every notice and error message.
> pattern NoticeCode = 0x43 :: NoticeFieldTag -- 'C'

> -- | (‘@M@’) The primary human-readable error message.
> --   It should be an accurate but terse (typically one line) statement of the underlying
> --   condtion. This field should be present in every notice and error message.
> pattern NoticeMessage = 0x4D :: NoticeFieldTag -- 'M'

> -- | (‘@D@’) An optional secondary error message carrying more detail about the problem.
> --   may contain newline characters, which should, however, be interpreted as paragraph
> --   rather than line breaks, so that user interfaces should feel free to wrap long
> --   descriptions to their display width as appropriate.
> pattern NoticeDetail = 0x44 :: NoticeFieldTag -- 'D'

> -- | (‘@H@’) An optional suggestion what to do about the problem.
> --   This is intended to differ from 'NoticeDetail' in that it offers advice (potentially inappropriate)
> --   rather than hard facts. Like 'NoticeDetail', the field's value may contain newline characters,
> --   which should, be interpreted as paragraph rather than line breaks, with long hints wrapped
> --   to the user interface's display width as appropriate.
> pattern NoticeHint = 0x48 :: NoticeFieldTag -- 'H'

> -- | (‘@P@’) A decimal ASCII integer indicating a character (not byte) index into the query string
> --   at which the error has been detected. The first character of the query is taken to be located
> --   at postion “@1@”.
> pattern NoticePosition = 0x50 :: NoticeFieldTag -- 'P'

> -- | (‘@p@’) A decimal ASCII integer indicating a character (not byte) index into an internally-generated
> --   query string at which the error has been detected. The first character of the query is taken to be located
> --   at postion “@1@”. This is the same as 'NoticePosition' but included for internally-generated
> --   queries, whose values will always be provided separated in the 'NoticeInternalQuery' field.
> pattern NoticeInternalPosition = 0x70 :: NoticeFieldTag -- 'p'

> -- | (‘@q@’) The text of a failed internally-generated SQL command.
> --   This could be, for example, a SQL query issued by a PL/pgSQL function.
> pattern NoticeInternalQuery = 0x71 :: NoticeFieldTag -- 'q'

> -- | (‘@W@’) An indication of the context in which the error occurred.
> --   Presently this includes a call stack traceback of active procedural language functions
> --   and internally-generated queries. The trace is one entry per line, most recent first.
> pattern NoticeContext = 0x57 :: NoticeFieldTag -- 'W'

> -- | (‘@s@’) If the error was associated with a specific database object,
> ---  the name of the schema containing that object, if any.
> pattern NoticeSchema = 0x73 :: NoticeFieldTag -- 's'

> -- | (‘@t@’) If the error was associated with a specific table, the name of the table
> --   within the schema specified separately by the 'NoticeSchema' field.
> pattern NoticeTable = 0x74 :: NoticeFieldTag -- 't'

> -- | (‘@c@’) If the error was associated with a specific table column, the name of the column
> --   within the table specified separately by the 'NoticeTable' and 'NoticeSchema' fields.
> pattern NoticeColumn = 0x63 :: NoticeFieldTag -- 'c'

> -- | (‘@d@’) If the error was associated with a specific data type, the name of the data type
> --   ithin the schema specified separately by the 'NoticeSchema' field.
> pattern NoticeDataType = 0x64 :: NoticeFieldTag -- 'd'

> -- | (‘@n@’) If the error was associated with a specific constraint, the name of the constraint or index
> --   on the database object specified separately by the 'NoticeSchema', 'NotieTable', 'NoticeColumn' and/or 'NoticeDataType' fields.
> pattern NoticeConstraint = 0x6E :: NoticeFieldTag -- 'n'

> -- | (‘@F@’) The file name of the source-code location where the error was reported.
> pattern NoticeFile = 0x46 :: NoticeFieldTag -- 'F'

> -- | (‘@L@’) The line number of the source-code location where the error was reported.
> pattern NoticeLine = 0x4C :: NoticeFieldTag -- 'L'

> -- | (‘@R@’) The name of the source-code routine reporting the error.
> pattern NoticeRoutine = 0x52 :: NoticeFieldTag -- 'R'


  Miscellaneous Types
  ===================

> -- | Type used to identify asynchronous notification channels bound by SQL @LISTEN@ command.
> type ChannelName = ByteString

> -- | Type used to identify columns of a table by their numeric index, counting from @1@.
> type ColumnID = Int16

> -- | Raw encoded table data exchanged by 'CopyInData' and 'CopyOutData' messages.
> type DataString = Lazy.ByteString

> -- | Type used to identify result fields by their name.
> type FieldName = ByteString

> -- | Type used to identify PostgreSQL database objects.
> type ObjectID = Word32

> -- | Type used to identify PostgreSQL backend processes.
> type ProcessID = Word32

> -- | Raw SQL query or command.
> type QueryString = Lazy.ByteString

> -- | Result tag of an SQL query returned in a 'CommandComplete' message.
> --
> --   This is usually a terse but human-readable string describing the nature
> --   of the operation performed and the number of result rows affected:
> --
> --   * For single-row @INSERT@ commands into a table with row-level object identifiers (OIDs),
> --     the tag has the form “@INSERT /oid/ 1@”, where @/oid/@ is the object ID of the inserted row.
> --   * For all other @INSERT@ commands, the tag has the form “@INSERT 0 /n/@”, where @/n/@ is
> --     the number of rows inserted by the query.
> --   * For @DELETE@ commands, the tag has the form “@DELETE /n/@”, where @/n/@ is the number of rows deleted.
> --   * For @UPDATE@ commands, the tag has the form “@UPDATE /n/@”, where @/n/@ is the number of rows updated.
> --   * For @SELECT@ and @CREATE TABLE AS@ commands, the tag has the form “@SELECT /n/@”, where @/n/@ is the number of rows retrieved.
> --   * For @MOVE@ commands, the tag has the form “@MOVE /n/@”, where @/n/@ is the number of rows by which the cursor's position has been changed.
> --   * For @FETCH@ commands, the tag has the form “@FETCH /n/@”, where @/n/@ is the number of rows that have been retrieved from the cursor.
> --   * For @COPY@ commands, the tag has the form “@COPY /n/@”, where @/n/@ is the number of rows copied,
> --     or “@COPY@” (without the row count) in version of the PostgreSQL server prior to 8.2.
> type ResultTag = Lazy.ByteString

> -- | Session parameters are identified by strict byte strings.
> type ParameterName = ByteString

> -- | NUL-terminated runtime parameter value, represented by a lazy byte string.
> type ValueString = Lazy.ByteString
