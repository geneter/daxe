/*
  This file is part of Daxe.

  Daxe is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Daxe is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Daxe.  If not, see <http://www.gnu.org/licenses/>.
*/

part of wxs;


class WXSRestriction extends WXSAnnotated implements WithSubElements, Parent {

  // simpleType?, (minExclusive|minInclusive|maxExclusive|maxInclusive|totalDigits|fractionDigits|length|minLength|maxLength|enumeration|pattern)*
  // or: (group|all|choice|sequence)?, (attribute|attributeGroup)*
  WXSSimpleType _simpleType = null;
  List<WXSFacet> _facets;
  WithSubElements _model = null; // WXSGroup | WXSAll | WXSChoice | WXSSequence
  List<WXSThing> _attrDecls; // attrDecls: (attribute|attributeGroup)*
  String _base = null;

  WXSType _wxsBase = null;

  Element _domElement;
  WXSComplexContent _parent;


  WXSRestriction(final Element el, final WXSComplexContent parent, final WXSSchema schema) {
    _parseAnnotation(el);
    _facets = new List<WXSFacet>();
    _attrDecls = new List<WXSThing>();
    for (Node n = el.firstChild; n != null; n=n.nextSibling) {
      if (n is Element) {
        String localName = n.localName;
        if (localName == "simpleType")
          _simpleType = new WXSSimpleType(n, this, schema);
        else if (localName == "minExclusive")
          _facets.add(new WXSFacet(n));
        else if (localName == "minInclusive")
          _facets.add(new WXSFacet(n));
        else if (localName == "maxExclusive")
          _facets.add(new WXSFacet(n));
        else if (localName == "maxInclusive")
          _facets.add(new WXSFacet(n));
        else if (localName == "totalDigits")
          _facets.add(new WXSFacet(n));
        else if (localName == "fractionDigits")
          _facets.add(new WXSFacet(n));
        else if (localName == "length")
          _facets.add(new WXSFacet(n));
        else if (localName == "minLength")
          _facets.add(new WXSFacet(n));
        else if (localName == "maxLength")
          _facets.add(new WXSFacet(n));
        else if (localName == "enumeration")
          _facets.add(new WXSFacet(n));
        else if (localName == "pattern")
          _facets.add(new WXSFacet(n));
        else if (localName == "group")
          _model = new WXSGroup(n, this, schema);
        else if (localName == "all")
          _model = new WXSAll(n, this, schema);
        else if (localName == "choice")
          _model = new WXSChoice(n, this, schema);
        else if (localName == "sequence")
          _model = new WXSSequence(n, this, schema);
        else if (localName == "attribute")
          _attrDecls.add(new WXSAttribute(n, this, schema));
        else if (localName == "attributeGroup")
          _attrDecls.add(new WXSAttributeGroup(n, this, schema));
      }
    }
    if (el.hasAttribute("base"))
      _base = el.getAttribute("base");

    _domElement = el;
    this._parent = parent;
  }

  // from WithSubElements
  void resolveReferences(final WXSSchema schema, final WXSThing redefine) {
    if (_simpleType != null)
      _simpleType.resolveReferences(schema, redefine);
    if (_model != null)
      _model.resolveReferences(schema, redefine);
    for (WXSThing attrDecl in _attrDecls) {
      if (attrDecl is WXSAttribute)
        attrDecl.resolveReferences(schema);
      else if (attrDecl is WXSAttributeGroup)
        attrDecl.resolveReferences(schema, redefine);
    }
    if (_base != null) {
      final String tns = _domElement.lookupNamespaceURI(DaxeWXS._namePrefix(_base));
      _wxsBase = schema.resolveTypeReference(DaxeWXS._localValue(_base), tns, redefine);
    }
  }

  // from WithSubElements
  List<WXSElement> allElements() {
    final List<WXSElement> list = new List<WXSElement>();
    if (_model != null)
      list.addAll(_model.allElements());
    return(list);
  }

  // from WithSubElements
  List<WXSElement> subElements() {
    final List<WXSElement> list = new List<WXSElement>();
    if (_model != null)
      list.addAll(_model.subElements());
    return(list);
  }

  // from Parent
  List<WXSElement> parentElements() {
    if (_parent is WXSComplexContent)
      return(_parent.parentElements());
    else
      return(new List<WXSElement>());
  }

  // from WithSubElements
  String regularExpression() {
    if (_model != null)
      return(_model.regularExpression());
    return(null);
  }

  // from WithSubElements
  bool requiredChild(final WXSElement child) {
    // returns null if child is not a child
    if (_model != null)
      return(_model.requiredChild(child));
    return(null);
  }

  // from WithSubElements
  bool multipleChildren(final WXSElement child) {
    // returns null if child is not a child
    if (_model != null)
      return(_model.multipleChildren(child));
    return(null);
  }

  List<String> possibleValues() {
    List<String> list = null;
    for (WXSFacet facet in _facets) {
      if (facet.getFacet() == "enumeration") {
        if (list == null)
          list = new List<String>();
        list.add(facet.getValue());
      }
    }
    return(list);
  }

  List<String> suggestedValues() {
    return(possibleValues());
  }

  List<WXSAttribute> attributes() {
    final List<WXSAttribute> list = new List<WXSAttribute>();
    for (WXSThing attrDecl in _attrDecls) {
      if (attrDecl is WXSAttribute)
        list.add(attrDecl);
      else if (attrDecl is WXSAttributeGroup)
        list.addAll(attrDecl.attributes());
    }
    if (_wxsBase is WXSComplexType) {
      final List<WXSAttribute> baseList = (_wxsBase as WXSComplexType).attributes();
      final List<WXSAttribute> toRemove = new List<WXSAttribute>();
      for (WXSAttribute attributRest in list) {
        final String extName = attributRest.getName();
        final bool prohibited = attributRest.getUse() == "prohibited";
        for (WXSAttribute attributBase in baseList)
          if (extName == attributBase.getName()) {
            if (prohibited)
              toRemove.add(attributBase);
            else
              baseList[baseList.indexOf(attributBase)] = attributRest;
            break;
          }
      }
      for (WXSAttribute attribut in toRemove)
        baseList.remove(attribut);
      return(baseList);
    }
    return(list);
  }

  // from WithSubElements
  int validate(final List<WXSElement> subElements, final int start, final bool insertion) {
    if (_model == null)
      return(start);
    return(_model.validate(subElements, start, insertion));
  }

  // from WithSubElements
  bool isOptionnal() {
    if (_model != null)
      return(_model.isOptionnal());
    return(true);
  }

  bool validValue(final String value) {
    if (_wxsBase != null) {
      if (!_wxsBase.validValue(value))
        return(false);
    }
    bool enumerationOrPattern = false;
    for (final WXSFacet facet in _facets) {
      if (facet.getFacet() == "enumeration") {
        if (facet.validValue(value))
          return(true);
        enumerationOrPattern = true;
      } else if (facet.getFacet() == "pattern") {
        if (facet.validValue(value))
          return(true);
        enumerationOrPattern = true;
      } else if (!facet.validValue(value))
        return(false);
    }
    if (enumerationOrPattern)
      return(false);
    return(true);
  }
}
