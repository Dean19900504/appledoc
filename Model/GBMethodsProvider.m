//
//  GBMethodsProvider.m
//  appledoc
//
//  Created by Tomaz Kragelj on 26.7.10.
//  Copyright (C) 2010, Gentle Bytes. All rights reserved.
//

#import "GBMethodData.h"
#import "GBMethodSectionData.h"
#import "GBMethodsProvider.h"

@interface GBMethodsProvider ()

- (void)addMethod:(GBMethodData *)method toSortedArray:(NSMutableArray *)array;

@end

#pragma mark -

@implementation GBMethodsProvider

#pragma mark Initialization & disposal

- (id)initWithParentObject:(id)parent {
	NSParameterAssert(parent != nil);
	GBLogDebug(@"Initializing methods provider for %@...", parent);
	self = [super init];
	if (self) {
		_parent = [parent retain];
		_sections = [[NSMutableArray alloc] init];
		_methods = [[NSMutableArray alloc] init];
		_classMethods = [[NSMutableArray alloc] init];
		_instanceMethods = [[NSMutableArray alloc] init];
		_properties = [[NSMutableArray alloc] init];
		_methodsBySelectors = [[NSMutableDictionary alloc] init];
		_sectionsByNames = [[NSMutableDictionary alloc] init];
	}
	return self;
}

#pragma mark Registration methods

- (GBMethodSectionData *)registerSectionWithName:(NSString *)name {
	GBLogDebug(@"%@: Registering section %@...", _parent, name ? name : @"default");
	GBMethodSectionData *section = [[[GBMethodSectionData alloc] init] autorelease];
	section.sectionName = name;
	_registeringSection = section;
	[_sections addObject:section];
	if (name) [_sectionsByNames setObject:section forKey:name];
	return section;
}

- (GBMethodSectionData *)registerSectionIfNameIsValid:(NSString *)string {
	if (!string) return nil;
	string = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([string length] == 0) return nil;
	return [self registerSectionWithName:string];
}

- (void)registerMethod:(GBMethodData *)method {
	// Note that we allow adding several methods with the same selector as long as the type is different (i.e. class and instance methods). In such case, methodBySelector will preffer instance method or property to class method! Note that this could be implemented more inteligently by prefixing selectors with some char or similar and then handling that within methodBySelector: and prefer instance/property in there. However at the time being current code seems sufficient and simpler, so let's stick with it for a while...
	NSParameterAssert(method != nil);
	GBLogDebug(@"%@: Registering method %@...", _parent, method);
	if ([_methods containsObject:method]) return;
	GBMethodData *existingMethod = [_methodsBySelectors objectForKey:method.methodSelector];
	if (existingMethod && existingMethod.methodType == method.methodType) {
		[existingMethod mergeDataFromObject:method];
		return;
	}
	
	method.parentObject = _parent;
	[_methods addObject:method];	
	if ([self.sections count] == 0) _registeringSection = [self registerSectionWithName:nil];
	if (!_registeringSection) _registeringSection = [self.sections lastObject];
	[_registeringSection registerMethod:method];
	
	switch (method.methodType) {
		case GBMethodTypeClass:
			[self addMethod:method toSortedArray:_classMethods];
			break;
		case GBMethodTypeInstance:
			[self addMethod:method toSortedArray:_instanceMethods];
			break;
		case GBMethodTypeProperty:
			[self addMethod:method toSortedArray:_properties];
			break;
	}
	
	if (existingMethod && existingMethod.methodType != GBMethodTypeClass) return;
	[_methodsBySelectors setObject:method forKey:method.methodSelector];
}

- (void)unregisterMethod:(GBMethodData *)method {
	// Remove from all our lists.
	[_methods removeObject:method];
	[_classMethods removeObject:method];
	[_instanceMethods removeObject:method];
	[_properties removeObject:method];
	
	// Ask all sections to remove the method from their lists.
	[_sections enumerateObjectsUsingBlock:^(GBMethodSectionData *section, NSUInteger idx, BOOL *stop) {
		if ([section unregisterMethod:method]) {
			if ([section.methods count] == 0) {
				[_sections removeObject:section];
				if (section.sectionName) [_sectionsByNames removeObjectForKey:section.sectionName];
			}
			*stop = YES;
		}
	}];
}

- (void)addMethod:(GBMethodData *)method toSortedArray:(NSMutableArray *)array {
	[array addObject:method];
	[array sortUsingComparator:^(GBMethodData *obj1, GBMethodData *obj2) {
		return [obj1.methodSelector compare:obj2.methodSelector];
	}];
}

#pragma mark Output generation helpers

- (BOOL)hasSections {
	return ([self.sections count] > 0);
}

- (BOOL)hasMultipleSections {
	return ([self.sections count] > 1);
}

- (BOOL)hasClassMethods {
	return ([self.classMethods count] > 0);
}

- (BOOL)hasInstanceMethods {
	return ([self.instanceMethods count] > 0);
}

- (BOOL)hasProperties {
	return ([self.properties count] > 0);
}

#pragma mark Helper methods

- (void)mergeDataFromMethodsProvider:(GBMethodsProvider *)source {
	// If a method with the same selector is found while merging from source, we should check if the type also matches. If so, we can merge the data from the source's method. However if the type doesn't match, we should ignore the method alltogether (ussually this is due to custom property implementation). We should probably deal with this scenario more inteligently, but it seems it works...
	if (!source || source == self) return;
	GBLogDebug(@"%@: Merging methods from %@...", _parent, source->_parent);
	GBMethodSectionData *previousSection = _registeringSection;
	[source.sections enumerateObjectsUsingBlock:^(GBMethodSectionData *sourceSection, NSUInteger idx, BOOL *stop) {
		GBMethodSectionData *existingSection = [_sectionsByNames objectForKey:sourceSection.sectionName];
		if (!existingSection) existingSection = [self registerSectionWithName:sourceSection.sectionName];
		_registeringSection = existingSection;
		
		[sourceSection.methods enumerateObjectsUsingBlock:^(GBMethodData *sourceMethod, NSUInteger idx, BOOL *stop) {
			GBMethodData *existingMethod = [_methodsBySelectors objectForKey:sourceMethod.methodSelector];
			if (existingMethod) {
				if (existingMethod.methodType == sourceMethod.methodType) [existingMethod mergeDataFromObject:sourceMethod];
				return;
			}
			[self registerMethod:sourceMethod];
		}];
	}];
	_registeringSection = previousSection;
}

- (GBMethodData *)methodBySelector:(NSString *)selector {
	return [_methodsBySelectors objectForKey:selector];
}

#pragma mark Overriden methods

- (NSString *)description {
	return [_parent description];
}

#pragma mark Properties

@synthesize methods = _methods;
@synthesize classMethods = _classMethods;
@synthesize instanceMethods = _instanceMethods;
@synthesize properties = _properties;
@synthesize sections = _sections;

@end
