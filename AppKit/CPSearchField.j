/*
 * CPSearchField.j
 * AppKit
 *
 * Created by cacaodev.
 * Copyright 2009.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

@import "CPButton.j"
@import "CPMenu.j"
@import "CPMenuItem.j"
@import "CPTextField.j"
@import "CPAnimationContext.j"
@import "CPViewAnimator.j"
@import "CPArrayController.j"

@class CPUserDefaults
@class CALayer

@global CPApp

CPSearchFieldRecentsTitleMenuItemTag    = 1000;
CPSearchFieldRecentsMenuItemTag         = 1001;
CPSearchFieldClearRecentsMenuItemTag    = 1002;
CPSearchFieldNoRecentsMenuItemTag       = 1003;

var CPAutosavedRecentsChangedNotification = @"CPAutosavedRecentsChangedNotification";

/*!
    @ingroup appkit
    @class CPSearchField
    The CPSearchField class defines the programmatic interface for text fields that are optimized for text-based searches. A CPSearchField object directly inherits from the CPTextField class. The search field implemented by these classes presents a standard user interface for searches, including a search button, a cancel button, and a pop-up icon menu for listing recent search strings and custom search categories.

    When the user types and then pauses, the text field's action message is sent to its target. You can query the text field's string value for the current text to search for. Do not rely on the sender of the action to be an CPMenu object because the menu may change. If you need to change the menu, modify the search menu template and call the setSearchMenuTemplate: method to update.
*/
@implementation CPSearchField : CPTextField
{
    CPButton    _searchButton;
    CPButton    _cancelButton;
    CPMenu      _searchMenuTemplate;
    CPMenu      _searchMenu;

    CPString    _recentsAutosaveName;
    CPArray     _recentSearches;

    int         _maximumRecents;
    BOOL        _sendsWholeSearchString;
    BOOL        _sendsSearchStringImmediately;
    BOOL        _canResignFirstResponder;
    CPTimer     _partialStringTimer;

    CPView      _contentView;
    BOOL        _isBecomingFirstResponder;
}

+ (CPString)defaultThemeClass
{
    return @"searchfield"
}

+ (CPDictionary)themeAttributes
{
    return @{
            @"image-search": [CPNull null],
            @"image-find": [CPNull null],
            @"image-cancel": [CPNull null],
            @"image-cancel-pressed": [CPNull null],
            @"image-search-inset" : CGInsetMake(0, 0, 0, 5),
            @"image-cancel-inset" : CGInsetMake(0, 5, 0, 0),
            @"search-button-rect-function": [CPNull null],
            @"layout-function": [CPNull null],
            @"search-right-margin": 2,
            @"search-menu-offset": CGPointMake(10, -4)
        };
}

+ (Class)_binderClassForBinding:(CPString)aBinding
{
    if (aBinding === CPPredicateBinding)
        return [_CPSearchFieldPredicateBinder class];

    return [super _binderClassForBinding:aBinding];
}

- (id)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame])
    {
        _maximumRecents = 10;
        _sendsWholeSearchString = NO;
        _sendsSearchStringImmediately = NO;
        _recentsAutosaveName = nil;

        [self _init];
    }

    return self;
}

- (void)_init
{
    _recentSearches = [CPArray array];

    [self setBezeled:YES];
    [self setBezelStyle:CPTextFieldRoundedBezel];
    [self setBordered:YES];
    [self setEditable:YES];
    [self setContinuous:YES];

    var bounds = [self bounds],
        cancelButton = [[CPButton alloc] initWithFrame:[self cancelButtonRectForBounds:bounds]],
        searchButton = [[CPButton alloc] initWithFrame:[self searchButtonRectForBounds:bounds]];

    [self setCancelButton:cancelButton];
    [self resetCancelButton];

    [self setSearchButton:searchButton];
    [self resetSearchButton];

    _canResignFirstResponder = YES;
    _isBecomingFirstResponder = NO;
}


#pragma mark -
#pragma mark Override observers

- (void)_removeObservers
{
    if (!_isObserving)
        return;

    [super _removeObservers];

    [[CPNotificationCenter defaultCenter] removeObserver:self name:CPControlTextDidChangeNotification object:self];
}

- (void)_addObservers
{
    if (_isObserving)
        return;

    [super _addObservers];

    [[CPNotificationCenter defaultCenter] addObserver:self selector:@selector(_searchFieldTextDidChange:) name:CPControlTextDidChangeNotification object:self];
}

// Managing Buttons
/*!
    Sets the button used to display the search-button image
    @param button The search button.
*/
- (void)setSearchButton:(CPButton)button
{
    if (button != _searchButton)
    {
        [_searchButton removeFromSuperview];
        _searchButton = button;

        [_searchButton setFrame:[self searchButtonRectForBounds:[self bounds]]];
        [_searchButton setAutoresizingMask:CPViewMaxXMargin];
        [self addSubview:_searchButton];
    }
}

/*!
    Returns the button used to display the search-button image.
    @return The search button.
*/
- (CPButton)searchButton
{
    return _searchButton;
}

/*!
    Resets the search button to its default attributes.
    This method resets the target, action, regular image, and pressed image. By default, when users click the search button or press the Return key, the action defined for the receiver is sent to its designated target. This method gives you a way to customize the search button for specific situations and then reset the button defaults without having to undo changes individually.
*/
- (void)resetSearchButton
{
    var button = [self searchButton],
        searchButtonImage = (_searchMenuTemplate == nil) ? [self currentValueForThemeAttribute:@"image-search"] : [self currentValueForThemeAttribute:@"image-find"];

    [button setBordered:NO];
    [button setImageScaling:CPImageScaleAxesIndependently];
    [button setImage:searchButtonImage];
    [button setAutoresizingMask:CPViewMaxXMargin];
}

/*!
    Sets the button object used to display the cancel-button image.
    @param button The cancel button.
*/
- (void)setCancelButton:(CPButton)button
{
    if (button != _cancelButton)
    {
        [_cancelButton removeFromSuperview];
        _cancelButton = button;

        [_cancelButton setFrame:[self cancelButtonRectForBounds:[self bounds]]];
        [_cancelButton setAutoresizingMask:CPViewMinXMargin];
        [_cancelButton setTarget:self];
        [_cancelButton setAction:@selector(cancelOperation:)];
        [_cancelButton setButtonType:CPMomentaryChangeButton];
        [self _updateCancelButtonVisibility];
        [self addSubview:_cancelButton];
    }
}

/*!
    Returns the button object used to display the cancel-button image.
    @return The cancel button.
*/
- (CPButton)cancelButton
{
    return _cancelButton;
}

/*!
    Resets the cancel button to its default attributes.
    This method resets the target, action, regular image, and pressed image. This method gives you a way to customize the cancel button for specific situations and then reset the button defaults without having to undo changes individually.
*/
- (void)resetCancelButton
{
    var button = [self cancelButton];
    [button setBordered:NO];
    [button setImageScaling:CPImageScaleAxesIndependently];
    [button setImage:[self currentValueForThemeAttribute:@"image-cancel"]];
    [button setAlternateImage:[self currentValueForThemeAttribute:@"image-cancel-pressed"]];
    [button setAutoresizingMask:CPViewMinXMargin];
    [button setTarget:self];
    [button setAction:@selector(cancelOperation:)];
}

// Custom Layout
/*!
    Modifies the bounding rectangle for the search-text field.
    @param rect The current bounding rectangle for the search text field.
    @return The updated bounding rectangle to use for the search text field. The default value is the value passed into the rect parameter.
    Subclasses can override this method to return a new bounding rectangle for the text-field object. You might use this method to provide a custom layout for the search field control.
*/
- (CGRect)searchTextRectForBounds:(CGRect)rect
{
    var leftOffset = 0,
        width = CGRectGetWidth(rect),
        bounds = [self bounds];

    if (_searchButton)
    {
        var searchBounds = [self searchButtonRectForBounds:bounds],
            rightMargin  = [self _potentialCurrentValueForThemeAttribute:@"search-right-margin"];
        leftOffset = CGRectGetMaxX(searchBounds) + rightMargin;
    }

    if (_cancelButton)
    {
        var cancelRect = [self cancelButtonRectForBounds:bounds];
        width = CGRectGetMinX(cancelRect) - leftOffset;
    }

    return CGRectMake(leftOffset, CGRectGetMinY(rect), width, CGRectGetHeight(rect));
}

/*!
    Modifies the bounding rectangle for the search button.
    @param rect The current bounding rectangle for the search button.
    Subclasses can override this method to return a new bounding rectangle for the search button. You might use this method to provide a custom layout for the search field control.
*/
- (CGRect)searchButtonRectForBounds:(CGRect)rect
{
    var themedRectFunction = [self _potentialCurrentValueForThemeAttribute:@"search-button-rect-function"];

    if (themedRectFunction)
        // There's a theme defined positioning function, just use it
        return objj_eval("("+themedRectFunction+")")(self, rect);
    else
    {
        var size = [[self _potentialCurrentValueForThemeAttribute:@"image-search"] size] || CGSizeMakeZero(),
            inset = [self _potentialCurrentValueForThemeAttribute:@"image-search-inset"];

        return CGRectMake(inset.left - inset.right, inset.top - inset.bottom + (CGRectGetHeight(rect) - size.height) / 2, size.width, size.height);
    }
}

/*!
    Modifies the bounding rectangle for the cancel button.
    @param rect The updated bounding rectangle to use for the cancel button. The default value is the value passed into the rect parameter.
    Subclasses can override this method to return a new bounding rectangle for the cancel button. You might use this method to provide a custom layout for the search field control.
*/
- (CGRect)cancelButtonRectForBounds:(CGRect)rect
{
    var size = [[self _potentialCurrentValueForThemeAttribute:@"image-cancel"] size] || CGSizeMakeZero(),
        inset = [self _potentialCurrentValueForThemeAttribute:@"image-cancel-inset"];

    return CGRectMake(CGRectGetWidth(rect) - size.width + inset.left - inset.right, inset.top - inset.bottom + (CGRectGetHeight(rect) - size.width) / 2, size.height, size.height);
}

// Managing Menu Templates
/*!
    Returns the menu template object used to dynamically construct the search pop-up icon menu.
    @return The current menu template.
*/
- (CPMenu)searchMenuTemplate
{
    return _searchMenuTemplate;
}

/*!
    Sets the menu template object used to dynamically construct the receiver's pop-up icon menu.
    @param menu The menu template to use.
    The receiver looks for the tag constants described in ŇMenu tagsÓ to determine how to populate the menu with items related to recent searches. See ŇConfiguring a Search MenuÓ for a sample of how you might set up the search menu template.
*/
- (void)setSearchMenuTemplate:(CPMenu)aMenu
{
    _searchMenuTemplate = aMenu;

    [self resetSearchButton];
    [self _loadRecentSearchList];
    [self _updateSearchMenu];
}

// Managing Search Modes
/*!
    Returns a Boolean value indicating whether the receiver sends the search action message when the user clicks the search button (or presses return) or after each keystroke.
    @return \c YES if the action message is sent all at once when the user clicks the search button or presses return; otherwise, NO if the search string is sent after each keystroke. The default value is NO.
*/
- (BOOL)sendsWholeSearchString
{
    return _sendsWholeSearchString;
}

/*!
    Sets whether the receiver sends the search action message when the user clicks the search button (or presses return) or after each keystroke.
    @param flag \c YES to send the action message all at once when the user clicks the search button or presses return; otherwise, NO to send the search string after each keystroke.
*/
- (void)setSendsWholeSearchString:(BOOL)flag
{
    _sendsWholeSearchString = flag;
}

/*!
    Returns a Boolean value indicating whether the receiver sends its action immediately upon being notified of changes to the search field text or after a brief pause.
    @return \c YES if the text field sends its action immediately upon notification of any changes to the search field; otherwise, NO.
*/
- (BOOL)sendsSearchStringImmediately
{
    return _sendsSearchStringImmediately;
}

/*!
    Sets whether the text field sends its action message to the target immediately upon notification of any changes to the search field text or after a brief pause.
    @param flag \c YES to send the text field's action immediately upon notification of any changes to the search field; otherwise, NO if you want the text field to pause briefly before sending its action message. Pausing gives the user the opportunity to type more text into the search field before initiating the search.
*/
- (void)setSendsSearchStringImmediately:(BOOL)flag
{
    _sendsSearchStringImmediately = flag;
}

// Managing Recent Search Strings
/*!
    Returns the maximum number of recent search strings to display in the custom search menu.
    @return The maximum number of search strings that can appear in the menu. This value is between 0 and 254.
*/
- (int)maximumRecents
{
    return _maximumRecents;
}

/*!
    Sets the maximum number of search strings that can appear in the search menu.
    @param maxRecents The maximum number of search strings that can appear in the menu. This value can be between 0 and 254. Specifying a value less than 0 sets the value to the default, which is 10. Specifying a value greater than 254 sets the maximum to 254.
*/
- (void)setMaximumRecents:(int)max
{
    if (max > 254)
        max = 254;
    else if (max < 0)
        max = 10;

    _maximumRecents = max;
}

/*!
    Returns the list of recent search strings for the control.
    @return An array of \c CPString objects, each of which contains a search string either displayed in the search menu or from a recent autosave archive. If there have been no recent searches and no prior searches saved under an autosave name, this array may be empty.
 */
- (CPArray)recentSearches
{
    return _recentSearches;
}

/*!
    Sets the list of recent search strings to list in the pop-up icon menu of the receiver.
    @param searches An array of CPString objects containing the search strings.
    You might use this method to set the recent list of searches from an archived copy.
*/
- (void)setRecentSearches:(CPArray)searches
{
    var max = MIN([self maximumRecents], [searches count]);

    _recentSearches = [searches subarrayWithRange:CPMakeRange(0, max)];
    [self _autosaveRecentSearchList];
}

/*!
    Returns the key under which the prior list of recent search strings has been archived.
    @return The autosave name, which is used as a key in the standard user defaults to save the recent searches. The default value is nil, which causes searches not to be autosaved.
*/
- (CPString)recentsAutosaveName
{
    return _recentsAutosaveName;
}

/*!
    Sets the autosave name under which the receiver automatically archives the list of recent search strings.
    @param name The autosave name, which is used as a key in the standard user defaults to save the recent searches. If you specify nil or an empty string for this parameter, no autosave name is set and searches are not autosaved.
*/
- (void)setRecentsAutosaveName:(CPString)name
{
    if (_recentsAutosaveName != nil)
        [self _deregisterForAutosaveNotification];

    _recentsAutosaveName = name;

    if (_recentsAutosaveName != nil)
      [self _registerForAutosaveNotification];
}

// Private methods and subclassing

- (CGRect)contentRectForBounds:(CGRect)bounds
{
    var superbounds = [super contentRectForBounds:bounds];
    return [self searchTextRectForBounds:superbounds];
}

+ (double)_keyboardDelayForPartialSearchString:(CPString)string
{
    return (6 - MIN([string length], 4)) / 10;
}

- (CPMenu)menu
{
    return _searchMenu;
}

- (BOOL)isOpaque
{
  return [super isOpaque] && [_cancelButton isOpaque] && [_searchButton isOpaque];
}

- (void)_updateCancelButtonVisibility
{
    [_cancelButton setHidden:([[self stringValue] length] === 0)];
}

- (void)_searchFieldTextDidChange:(CPNotification)aNotification
{
    if (![self sendsWholeSearchString])
    {
        if ([self sendsSearchStringImmediately])
            [self _sendPartialString];
        else
        {
            [_partialStringTimer invalidate];
            var timeInterval = [CPSearchField _keyboardDelayForPartialSearchString:[self stringValue]];

            _partialStringTimer = [CPTimer scheduledTimerWithTimeInterval:timeInterval
                                                                   target:self
                                                                 selector:@selector(_sendPartialString)
                                                                 userInfo:nil
                                                                  repeats:NO];
        }
    }

    [self _updateCancelButtonVisibility];
}

- (void)_sendAction:(id)sender
{
    [self sendAction:[self action] to:[self target]];
}

- (BOOL)sendAction:(SEL)anAction to:(id)anObject
{
    [self selectAll:nil];
    [super sendAction:anAction to:anObject];

    [_partialStringTimer invalidate];

    [self _addStringToRecentSearches:[self stringValue]];
    [self _updateCancelButtonVisibility];
}

- (void)_addStringToRecentSearches:(CPString)string
{
    if (string == nil || string === @"" || [_recentSearches containsObject:string])
        return;

    var searches = [CPMutableArray arrayWithArray:_recentSearches];
    [searches addObject:string];
    [self setRecentSearches:searches];
    [self _updateSearchMenu];
}

- (CPView)hitTest:(CGPoint)aPoint
{
    // Make sure a hit anywhere within the search field returns the search field itself
    if (CGRectContainsPoint([self frame], aPoint))
        return self;
    else
        return nil;
}

- (BOOL)resignFirstResponder
{
    return _canResignFirstResponder && [super resignFirstResponder];
}

- (void)mouseDown:(CPEvent)anEvent
{
    var location = [anEvent locationInWindow],
        point = [self convertPoint:location fromView:nil];

    if (CGRectContainsPoint([self searchButtonRectForBounds:[self bounds]], point))
    {
        if (_searchMenuTemplate == nil)
        {
            if ([_searchButton target] && [_searchButton action])
                [_searchButton mouseDown:anEvent];
            else
                [self _sendAction:self];
        }
        else
           [self _showMenu];
    }
    else if (CGRectContainsPoint([self cancelButtonRectForBounds:[self bounds]], point))
        [_cancelButton mouseDown:anEvent];
    else
        [super mouseDown:anEvent];
}

/*!
    Provides the common case items for a recent searches menu.

    If there are 1 more recent searches, it displays:

        Clear
        ---------------------
        Recent Searches
        recent search 1
        recent search 2
        etc.

    If you wish to add items before or after the template, you can. If you put items
    before, a separator will automatically be placed before the default template item.
    If you add items after the default template, it is your responsibility to add a separator.

    To add a custom item:

    item = [[CPMenuItem alloc] initWithTitle:@"google"
                                      action:@selector(google:)
                               keyEquivalent:@""];
    [item setTag:700];
    [item setTarget:self];
    [template addItem:item];

    Be sure that your custom items do not use tags in the range 1000-1003 inclusive.
    If you wish to maintain state in custom menu items that you add, you will need to maintain
    the item state yourself, then in the action method of the custom items, modify the items
    in the search menu template and send [searchField setSearchMenuTemplate:template] to update the menu.
*/
- (CPMenu)defaultSearchMenuTemplate
{
    var template = [[CPMenu alloc] init],
        item;

    item = [[CPMenuItem alloc] initWithTitle:@"Clear"
                                      action:@selector(_searchFieldClearRecents:)
                               keyEquivalent:@""];
    [item setTag:CPSearchFieldClearRecentsMenuItemTag];
    [item setTarget:self];
    [template addItem:item];

    [self _addSeparatorToMenu:template];

    item = [[CPMenuItem alloc] initWithTitle:@"Recent Searches"
                                      action:nil
                               keyEquivalent:@""];
    [item setTag:CPSearchFieldRecentsTitleMenuItemTag];
    [item setEnabled:NO];
    [template addItem:item];

    item = [[CPMenuItem alloc] initWithTitle:@"Recent search item"
                                      action:@selector(_searchFieldSearch:)
                               keyEquivalent:@""];
    [item setTag:CPSearchFieldRecentsMenuItemTag];
    [item setTarget:self];
    [template addItem:item];

    return template;
}

- (void)_updateSearchMenu
{
    if (_searchMenuTemplate == nil)
        return;

    var menu = [[CPMenu alloc] init],
        countOfRecents = [_recentSearches count],
        numberOfItems = [_searchMenuTemplate numberOfItems];

    [menu setAutoenablesItems:NO];

    for (var i = 0; i < numberOfItems; i++)
    {
        var item = [[_searchMenuTemplate itemAtIndex:i] copy];

        switch ([item tag])
        {
            case CPSearchFieldRecentsTitleMenuItemTag:
                if (countOfRecents === 0)
                    continue;
                break;

            case CPSearchFieldRecentsMenuItemTag:
            {
                var itemAction = @selector(_searchFieldSearch:);

                for (var recentIndex = 0; recentIndex < countOfRecents; ++recentIndex)
                {
                    var recentItem = [[CPMenuItem alloc] initWithTitle:[_recentSearches objectAtIndex:recentIndex]
                                                                 action:itemAction
                                                          keyEquivalent:[item keyEquivalent]];
                    [item setTarget:self];
                    [menu addItem:recentItem];
                }

                continue;
            }

            case CPSearchFieldClearRecentsMenuItemTag:
                if (countOfRecents === 0)
                    continue;

                [item setAction:@selector(_searchFieldClearRecents:)];
                [item setTarget:self];
                break;

            case CPSearchFieldNoRecentsMenuItemTag:
                if (countOfRecents !== 0)
                    continue;
                break;
            }

        [item setEnabled:([item isEnabled] && [item action] != nil && [item target] != nil)];
        [menu addItem:item];
    }

    [menu setDelegate:self];

    _searchMenu = menu;
}

- (void)_addSeparatorToMenu:(CPMenu)aMenu
{
    var separator = [CPMenuItem separatorItem];
    [separator setEnabled:NO];
    [separator setTag:CPSearchFieldRecentsTitleMenuItemTag];
    [aMenu addItem:separator];
}

- (void)menuWillOpen:(CPMenu)menu
{
    _canResignFirstResponder = NO;
}

- (void)menuDidClose:(CPMenu)menu
{
    _canResignFirstResponder = YES;

    [self becomeFirstResponder];
}

- (void)_showMenu
{
    if (_searchMenu === nil || [_searchMenu numberOfItems] === 0 || ![self isEnabled])
        return;

    var aFrame = [[self superview] convertRect:[self frame] toView:nil],
        offset = [self currentValueForThemeAttribute:@"search-menu-offset"],
        location = CGPointMake(aFrame.origin.x + offset.x, aFrame.origin.y + aFrame.size.height + offset.y);

    var anEvent = [CPEvent mouseEventWithType:CPRightMouseDown location:location modifierFlags:0 timestamp:[[CPApp currentEvent] timestamp] windowNumber:[[self window] windowNumber] context:nil eventNumber:1 clickCount:1 pressure:0];

    [self selectAll:nil];
    [CPMenu popUpContextMenu:_searchMenu withEvent:anEvent forView:self];
}

- (void)_sendPartialString
{
    [super sendAction:[self action] to:[self target]];
    [_partialStringTimer invalidate];
}

- (void)cancelOperation:(id)sender
{
    // If something was entered, the search field must deactivate itself (else, do nothing)
    if ([[self stringValue] length] > 0)
    {
        [self setObjectValue:@""];
        [self textDidChange:[CPNotification notificationWithName:CPControlTextDidChangeNotification object:self userInfo:nil]];

        [[self window] makeFirstResponder:[self window]];
    }
}

- (void)_searchFieldSearch:(id)sender
{
    var searchString = [sender title];

    if ([sender tag] != CPSearchFieldRecentsMenuItemTag)
        [self _addStringToRecentSearches:searchString];

    [self setObjectValue:searchString];
    [self _sendPartialString];
    [self selectAll:nil];

    [self _updateCancelButtonVisibility];
}

- (void)_searchFieldClearRecents:(id)sender
{
    [self setRecentSearches:[CPArray array]];
    [self _updateSearchMenu];
    [self setStringValue:@""];
    [self _updateCancelButtonVisibility];
 }

- (void)_registerForAutosaveNotification
{
    [[CPNotificationCenter defaultCenter] addObserver:self selector:@selector(_updateAutosavedRecents:) name:CPAutosavedRecentsChangedNotification object:_recentsAutosaveName];
}

- (void)_deregisterForAutosaveNotification
{
    [[CPNotificationCenter defaultCenter] removeObserver:self name:CPAutosavedRecentsChangedNotification object:_recentsAutosaveName];
}

- (void)_autosaveRecentSearchList
{
    if (_recentsAutosaveName != nil)
        [[CPNotificationCenter defaultCenter] postNotificationName:CPAutosavedRecentsChangedNotification object:_recentsAutosaveName];
}

- (void)_updateAutosavedRecents:(id)notification
{
    var name = [notification object];
    [[CPUserDefaults standardUserDefaults] setObject:_recentSearches forKey:name];
}

- (void)_loadRecentSearchList
{
    var name = [self recentsAutosaveName];
    if (name == nil)
        return;

    var list = [[CPUserDefaults standardUserDefaults] objectForKey:name];

    if (list != nil)
        _recentSearches = list;
}

@end

#pragma mark -

@implementation CPSearchField (ThemingAdditions)

// Overwrite CPTextField method to permit themed layout functions

- (void)layoutSubviews
{
    if (!_contentView)
    {
        // Search for the CPImageAndTextView subview of mine

        for (var i = 0, subviews = [self subviews], nb = [subviews count]; (!_contentView && (i < nb)); i++)
            if ([subviews[i] isKindOfClass:_CPImageAndTextView])
                _contentView = subviews[i];
    }

    var bezelColor = [self currentValueForThemeAttribute:@"bezel-color"];

    if ([bezelColor isCSSBased])
    {
        // CSS Styling
        // We don't need bezelView as we apply CSS styling directly on the search view itself

        [self _setBackgroundColor:bezelColor];

        if (!_contentView)
            _contentView = [self layoutEphemeralSubviewNamed:@"content-view"
                                                  positioned:CPWindowAbove
                             relativeToEphemeralSubviewNamed:nil];
    }
    else if (!_contentView)
    {
        var bezelView = [self layoutEphemeralSubviewNamed:@"bezel-view"
                                               positioned:CPWindowBelow
                          relativeToEphemeralSubviewNamed:@"content-view"];

        [bezelView setBackgroundColor:bezelColor];

        _contentView = [self layoutEphemeralSubviewNamed:@"content-view"
                                              positioned:CPWindowAbove
                         relativeToEphemeralSubviewNamed:@"bezel-view"];
    }

    if (_contentView)
    {
        [_contentView setHidden:(_stringValue && _stringValue.length > 0) && [self hasThemeState:CPThemeStateEditing]];

        [_contentView setText:[self hasThemeState:CPTextFieldStatePlaceholder] ? [self placeholderString] : _stringValue];
        [_contentView setTextColor:[self currentValueForThemeAttribute:@"text-color"]];
        [_contentView setFont:[self font]]; //[self currentValueForThemeAttribute:@"font"]];
        [_contentView setAlignment:[self currentValueForThemeAttribute:@"alignment"]];
        [_contentView setVerticalAlignment:[self currentValueForThemeAttribute:@"vertical-alignment"]];
        [_contentView setLineBreakMode:[self currentValueForThemeAttribute:@"line-break-mode"]];
        [_contentView setTextShadowColor:[self currentValueForThemeAttribute:@"text-shadow-color"]];
        [_contentView setTextShadowOffset:[self currentValueForThemeAttribute:@"text-shadow-offset"]];
    }

    if (_isEditing)
        [self _setCSSStyleForInputElement];

    [self updateSearchButton];
    [self updateTrackingAreas];
}

// As CPTextField redefines setBackgroundColor, we have to bypass it
- (void)_setBackgroundColor:(CPColor)aColor
{
    var grannyMethod         = class_getInstanceMethod([[self superclass] superclass], @selector(setBackgroundColor:)),
        grannyImplementation = method_getImplementation(grannyMethod);

    grannyImplementation(self, @selector(setBackgroundColor:), aColor);
}

- (void)_layoutSubviews
{
    var themedLayoutFunction = [self currentValueForThemeAttribute:@"layout-function"];

    if (themedLayoutFunction)
        // There's a theme defined layout function, just use it
        objj_eval("("+themedLayoutFunction+")")(self);
    else
        // Call directly the completion handler
        [self themedLayoutFunctionCompletionHandler];
}

- (void)updateSearchButton
{
    [_searchButton setImage:(_searchMenuTemplate ? [self currentValueForThemeAttribute:@"image-find"] : [self currentValueForThemeAttribute:@"image-search"])];
    [self updateTrackingAreas];
}

- (void)themedLayoutFunctionCompletionHandler
{
    if (_isBecomingFirstResponder)
    {
        _isBecomingFirstResponder = NO;

        // Call the real _becomeFirstKeyResponder to finish setting the input element
        [super _becomeFirstKeyResponder];

        // For some (unknown yet) reason, input field doesn't focus and text field visual state is not updated
        var element = [self _inputElement];
        element.focus();
        [self layoutSubviews];
        [CALayer runLoopUpdateLayers]; // Thank you @daboe01 for suggesting adding this
    }
    else
        [self layoutSubviews];
}

// We override CPTextField method in order to delay the display of the input element until the end of the animation
- (BOOL)_becomeFirstKeyResponder
{
    // As we have to return a result, we check if response could be NO

    if (![self _isWithinUsablePlatformRect] || ![self isEditable])
        return NO;

    // We are now sure that response will be YES
    _isBecomingFirstResponder = YES;

    // We have to do this now in order to avoid running conditions messing things among multiple textfields
    _stringValue = [self stringValue];
    var element = [self _inputElement];
    element.value = _stringValue;

    [self _layoutSubviews];

    return YES;
}

- (void)textDidEndEditing:(CPNotification)note
{
    if ([note object] != self)
        return;

    [self _layoutSubviews];
    [super textDidEndEditing:note];
}

- (void)_windowDidResignKey:(CPNotification)aNotification
{
    // When the window resigns key, if the search field is empty, it must cancel first responder
    if ([[self stringValue] length] == 0)
        [[self window] makeFirstResponder:[self window]];

    [super _windowDidResignKey:aNotification];
    [self _layoutSubviews];
}

- (void)setPlaceholderString:(CPString)aStringValue
{
    [super setPlaceholderString:aStringValue];
    [self _layoutContent];
}

- (void)_layoutContent
{
    [_searchButton setFrame:[self searchButtonRectForBounds:[self bounds]]];
    [_contentView  setFrame:[self contentRectForBounds:[self bounds]]];
    [_cancelButton setFrame:[self cancelButtonRectForBounds:[self bounds]]];
    [self updateTrackingAreas];
}

- (void)setFrameSize:(CGSize)aSize
{
    [super setFrameSize:aSize];
    [self _layoutContent];
}

- (id)_potentialCurrentValueForThemeAttribute:(CPString)aName
{
    if (_isBecomingFirstResponder)
        return [self valueForThemeAttribute:aName inState:[self themeState].and(CPThemeStateEditing)];
    else
        return [self currentValueForThemeAttribute:aName];
}

- (void)unbind:(CPString)aBinding
{
    [super unbind:aBinding];

    // our CPPredicateBinding binder adds a binding to the value.
    // this private binding has to be also removed
    if (aBinding === CPPredicateBinding)
        [[[self class] _binderClassForBinding:aBinding] unbind:CPValueBinding forObject:self];
}

@end

#pragma mark -

@implementation CPSearchField (CPTrackingArea)
{
    CPTrackingArea      _searchButtonTrackingArea;
    CPTrackingArea      _cancelButtonTrackingArea;
}

- (void)updateTrackingAreas
{
    if (_searchButtonTrackingArea)
    {
        [self removeTrackingArea:_searchButtonTrackingArea];
        _searchButtonTrackingArea = nil;
    }

    if (_cancelButtonTrackingArea)
    {
        [self removeTrackingArea:_cancelButtonTrackingArea];
        _cancelButtonTrackingArea = nil;
    }

    if (_searchButton)
    {
        _searchButtonTrackingArea = [[CPTrackingArea alloc] initWithRect:[_searchButton frame]
                                                                 options:CPTrackingCursorUpdate | CPTrackingActiveInKeyWindow
                                                                   owner:self
                                                                userInfo:@{ @"isButton": YES }];

        [self addTrackingArea:_searchButtonTrackingArea];
    }

    if (_cancelButton && ![_cancelButton isHidden])
    {
        _cancelButtonTrackingArea = [[CPTrackingArea alloc] initWithRect:[_cancelButton frame]
                                                                 options:CPTrackingCursorUpdate | CPTrackingActiveInKeyWindow
                                                                   owner:self
                                                                userInfo:@{ @"isButton": YES }];

        [self addTrackingArea:_cancelButtonTrackingArea];
    }

    [super updateTrackingAreas];
}

- (void)cursorUpdate:(CPEvent)anEvent
{
    if ([[[anEvent trackingArea] userInfo] objectForKey:@"isButton"])
        [[CPCursor arrowCursor] set];
    else
        [super cursorUpdate:anEvent];
}

@end

#pragma mark -

var CPRecentsAutosaveNameKey            = @"CPRecentsAutosaveNameKey",
    CPSendsWholeSearchStringKey         = @"CPSendsWholeSearchStringKey",
    CPSendsSearchStringImmediatelyKey   = @"CPSendsSearchStringImmediatelyKey",
    CPMaximumRecentsKey                 = @"CPMaximumRecentsKey",
    CPSearchMenuTemplateKey             = @"CPSearchMenuTemplateKey";

@implementation CPSearchField (CPCoding)

- (void)encodeWithCoder:(CPCoder)coder
{
    [_searchButton removeFromSuperview];
    [_cancelButton removeFromSuperview];

    [super encodeWithCoder:coder];

    if (_searchButton)
        [self addSubview:_searchButton];
    if (_cancelButton)
        [self addSubview:_cancelButton];

    [coder encodeBool:_sendsWholeSearchString forKey:CPSendsWholeSearchStringKey];
    [coder encodeBool:_sendsSearchStringImmediately forKey:CPSendsSearchStringImmediatelyKey];
    [coder encodeInt:_maximumRecents forKey:CPMaximumRecentsKey];

    if (_recentsAutosaveName)
        [coder encodeObject:_recentsAutosaveName forKey:CPRecentsAutosaveNameKey];

    if (_searchMenuTemplate)
        [coder encodeObject:_searchMenuTemplate forKey:CPSearchMenuTemplateKey];
}

- (id)initWithCoder:(CPCoder)coder
{
    if (self = [super initWithCoder:coder])
    {
        [self setRecentsAutosaveName:[coder decodeObjectForKey:CPRecentsAutosaveNameKey]];
        _sendsWholeSearchString   = [coder decodeBoolForKey:CPSendsWholeSearchStringKey];
        _sendsSearchStringImmediately = [coder decodeBoolForKey:CPSendsSearchStringImmediatelyKey];
        _maximumRecents           = [coder decodeIntForKey:CPMaximumRecentsKey];

        var template              = [coder decodeObjectForKey:CPSearchMenuTemplateKey];

        if (template)
            [self setSearchMenuTemplate:template];

        [self _init];
    }

    return self;
}

@end

@implementation _CPSearchFieldPredicateBinder : CPBinder
{
    CPArrayController  _controller;
    CPString           _predicateFormat;
}

- (void)setValue:(id)aValue forBinding:(CPString)aBinding
{
    if (aBinding === CPPredicateBinding)
    {
        var options = [_info objectForKey:CPOptionsKey];

        _controller = [_info objectForKey:CPObservedObjectKey];
        _predicateFormat = [options objectForKey:"CPPredicateFormat"];
        [_source bind:CPValueBinding toObject:self withKeyPath:"searchFieldValue" options:nil];
    }
}

- (void)setSearchFieldValue:(CPString)aValue
{
    var destination = [_info objectForKey:CPObservedObjectKey],
        keyPath     = [_info objectForKey:CPObservedKeyPathKey];

    [self suppressSpecificNotificationFromObject:destination keyPath:keyPath];

    if (aValue)
    {
        var values       = @[],
            formatString = _predicateFormat.replace(/\$value/g, function(x) {[values addObject:aValue]; return "%@";});

        [_controller setFilterPredicate:[CPPredicate predicateWithFormat:formatString argumentArray:values]];
    }
    else
        [_controller setFilterPredicate:nil];

    [self unsuppressSpecificNotificationFromObject:destination keyPath:keyPath];
}

- (CPString)searchFieldValue
{
    return [_source stringValue];
}

@end

