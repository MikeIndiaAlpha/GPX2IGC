#import <Foundation/Foundation.h>

@interface Fix : NSObject {
    double latitude;
    double longitude;
    double elevation;
    NSDate *time;
}

@property (readonly) double latitude;
@property (readonly) double longitude;
@property (readonly) double elevation;
@property (readonly) NSDate *time;

@end
@implementation  Fix

@synthesize latitude;
@synthesize longitude;
@synthesize elevation;
@synthesize time;

+ (Fix *)newWithLatitude: (double)latitude
               longitude: (double)longitude
               elevation: (double)elevation
                    time: (NSDate *)time
{
    Fix *fix = [Fix alloc];
    fix->latitude = latitude;
    fix->longitude = longitude;
    fix->elevation = elevation;
    fix->time = time;
    return fix;
}

@end

@interface GPXParser : NSObject<NSXMLParserDelegate> {
    // Data accumulated for current fix
    double elevation;
    BOOL hasElevation;
    NSDate *time;
    BOOL hasTime;
    double latitude;
    double longitude;
    BOOL hasLatitudeAndLongitude;
    // Parse utility variables
    NSMutableString *currentParsedCharactedData;
    NSDateFormatter *dateFormatter;
    BOOL errorOccured;
    // Data accumulated during the parse
    NSString *creator;
    NSMutableArray<Fix *> *fixes;
}

@property (readonly) NSString *creator;
@property (readonly) NSMutableArray<Fix *> *fixes;
@property (readonly) BOOL errorOccured;

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict;
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName;
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string;
- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError;
@end

@implementation GPXParser

@synthesize creator;
@synthesize fixes;
@synthesize errorOccured;

+ (GPXParser *)new
{
    GPXParser *gpx = [GPXParser alloc];
    // init parse variables
    gpx->errorOccured = NO;
    gpx->currentParsedCharactedData = [[NSMutableString alloc] init];
    gpx->dateFormatter = [[NSDateFormatter alloc] init];
    gpx->dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    gpx->dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    gpx->dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    // init output data
    gpx->creator = @"Unknown creator";
    gpx->fixes = [[NSMutableArray alloc] init];
    return gpx;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict
{
    if ([elementName isEqualToString: @"gpx"]) {
        NSString *creatorString = [attributeDict objectForKey: @"creator"];
        if (creatorString) {
            creator = creatorString;
        }
    } else if ([elementName isEqualToString: @"trkpt"]) {
        // Begin of GPS fix, reset state
        hasElevation = hasTime = hasLatitudeAndLongitude = NO;
        NSString *lat = [attributeDict objectForKey: @"lat"];
        NSString *lon = [attributeDict objectForKey: @"lon"];
        if (lat && lon) {
            hasLatitudeAndLongitude = YES;
            latitude = lat.doubleValue;
            longitude = lon.doubleValue;
        }
    } else {
        // new element, reset parsed character data
        [currentParsedCharactedData setString: @""];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    // Elevation and time are in their own XML elements, so need to get
    // currentParsedCharacterData on their ends
    if ([elementName isEqualToString: @"ele"]) {
        hasElevation = YES;
        elevation = currentParsedCharactedData.doubleValue;
    } else if ([elementName isEqualToString: @"time"]) {
        hasTime = YES;
        time = [dateFormatter dateFromString: currentParsedCharactedData];
    } else if ([elementName isEqualToString: @"trkpt"]) {
        // GPX fix ends
        if (hasTime && hasElevation && hasLatitudeAndLongitude) {
            Fix *fix = [Fix newWithLatitude: latitude
                                  longitude: longitude
                                  elevation: elevation
                                       time: time];
            [fixes addObject: fix];
        } else {
            NSLog(@"Incomplete GPS fix, skipping");
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    [currentParsedCharactedData appendString: string];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    NSLog(@"Parse error: %@", [parseError localizedDescription]);
    errorOccured = YES;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // // // // //
        // First part - parse input GPX file
        if (argc != 3) {
            NSLog(@"Usage: %s input.gpx output.igc", argv[0]);
            return -1;
        }
        // Make XML parser read from GPX file given in argv[1]
        NSString *input = [NSString stringWithUTF8String: argv[1]];
        NSString *output = [NSString stringWithUTF8String: argv[2]];
        NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath: input];
        [stream open];
        if (stream.streamError) {
            NSLog(@"Error opening GPX file \"%@\": %@", input, [stream.streamError localizedDescription]);
            return -1;
        }
        NSXMLParser *parser = [[NSXMLParser alloc] initWithStream: stream];
        // Create GPX2IGC class object and set it as the XML parser delegate
        GPXParser *gpx = [GPXParser new];
        parser.delegate = gpx;
        // Parse GPX XML
        [parser parse];
        // Tell the user about the results
        NSLog(@"%d GPS fixes read out of \"%@\" created by \"%@\", %@",
              (int)gpx.fixes.count, input, gpx.creator,
              gpx.errorOccured ? @"there were errors" : @"all ok");
        if (!gpx.fixes.count) {
            NSLog(@"No GPS fixes, nothing to do");
            return 0;
        }

        // // // // //
        // Second part, write IGC file with the data just parsed
        NSMutableString *igc = [[NSMutableString alloc] init];
        // Software signature
        [igc appendFormat: @"AXXXZZZgpx2igc by MichalA\r\n"];
        // Device signature
        [igc appendFormat: @"HFFTYFRTYPE: %@\r\n", gpx.creator];
        // UTC date of the flight
        NSDateFormatter *utcFormatter = [[NSDateFormatter alloc] init];
        utcFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT: 0];
        // UTC date
        utcFormatter.dateFormat = @"ddMMYY";
        [igc appendFormat: @"HFDTE%@\r\n", [utcFormatter stringFromDate: gpx.fixes.firstObject.time]];
        // all the fixes - but change date formatter to output UTC time now
        utcFormatter.dateFormat = @"HHmmss";
        for (Fix *fix in gpx.fixes) {
            // B-record timestamp part
            [igc appendFormat: @"B%@", [utcFormatter stringFromDate: fix.time]];
            // B-record latitude
            // IMPORTANT: both latitude and longitude coming from GPX stream are
            // in degrees (with fractions meaning fraction of degree). However,
            // IGC file wants them in degrees.seconds notation. So for example:
            // 49.50 in GPX means "49 and a half degree"
            // 49.50 in IGC means "49 and 50 minutes, so 5/6 of a degree"
            char northOrSouth = fix.latitude > 0.0 ? 'N' : 'S';
            double absoluteLatitude = fabs(fix.latitude);
            double latitudeDegrees = floor(absoluteLatitude);
            double latitudeFraction = absoluteLatitude - latitudeDegrees;
            int latitudeDegreesInt = (int)latitudeDegrees;
            int latitudeMinutesInt = (int)(latitudeFraction * 60000.0);
            [igc appendFormat: @"%.02d%.05d%c", latitudeDegreesInt, latitudeMinutesInt, northOrSouth];
            // B-record longitude
            char eastOrWest = fix.longitude > 0.0 ? 'E' : 'W';
            double absoluteLongitude = fabs(fix.longitude);
            double longitudeDegrees = floor(absoluteLongitude);
            double longitudeFraction = absoluteLongitude - longitudeDegrees;
            int longitudeDegreesInt = (int)longitudeDegrees;
            int longitudeMinutesInt = (int)(longitudeFraction * 60000.0);
            [igc appendFormat: @"%.03d%.05d%c", longitudeDegreesInt, longitudeMinutesInt, eastOrWest];
            // B-record AVFlag (3D validity)
            [igc appendFormat: @"A"];
            // B-record pressure and GPS altitudes
            int altitude = (int)(fix.elevation + 0.5);
            [igc appendFormat: @"%.05d%.05d\r\n", altitude, altitude];
        }
        // Need security key entry, supply invalid one
        [igc appendFormat: @"GInvalidSecurityKeyBecauseThisFileWasNotWrittenByValidLogger\r\n"];

        // Write IGC-formatted string to IGC file
        NSError *error = nil;
        if (![igc writeToFile: output
                   atomically: YES
                     encoding: NSUTF8StringEncoding
                        error: &error]) {
            NSLog(@"Error occured while trying to write IGC file \"%@\": %@",
                  output, [error localizedDescription]);
            return -1;
        }
        NSLog(@"IGC file \"%@\" written succesfully", output);
    }
    return 0;
}
