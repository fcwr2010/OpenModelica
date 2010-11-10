/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-CurrentYear, Link�ping University,
 * Department of Computer and Information Science,
 * SE-58183 Link�ping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 
 * AND THIS OSMC PUBLIC LICENSE (OSMC-PL). 
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES RECIPIENT'S  
 * ACCEPTANCE OF THE OSMC PUBLIC LICENSE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from Link�ping University, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or  
 * http://www.openmodelica.org, and in the OpenModelica distribution. 
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS
 * OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

package ConnectUtil
" file:        ConnectUtil.mo
  package:     ConnectUtil
  description: Connection set management

  RCS: $Id$

  Connections generate connection sets (datatype SET is described in Connect)
  which are constructed during instantiation.  When a connection
  set is generated, it is used to create a number of equations.
  The kind of equations created depends on the type of the set.

  ConnectUtil.mo is called from Inst.mo and is responsible for
  creation of all connect-equations later passed to the DAE module
  in DAEUtil.mo."

// public imports
public import Absyn;
public import ClassInf;
public import Connect;
public import DAE;
public import Env;
public import InnerOuter;
public import Prefix;

// protected imports
protected import ComponentReference;
protected import DAEUtil;
protected import Debug;
protected import Dump;
protected import Error;
protected import Expression;
protected import Lookup;
protected import PrefixUtil;
protected import Print;
protected import RTOpts;
protected import SCode;
protected import Static;
protected import Types;
protected import Util;

public
type AvlTree = Env.AvlTree;
type Cache   = Env.Cache;

protected function setConnectSets
  "Sets the connection set part of a Connect.Sets."
  input Connect.Sets inCS;
  input list<Connect.Set> inSets;
  output Connect.Sets outCS;

  list<DAE.ComponentRef> c, d;
  list<Connect.OuterConnect> o;
  list<Connect.StreamFlowConnect> sf;
algorithm
  Connect.SETS(_, c, d, o, sf) := inCS;
  outCS := Connect.SETS(inSets, c, d, o, sf);
end setConnectSets;

protected function addConnectSet
  "Adds a connection set to a Connect.Sets."
  input Connect.Sets inCS;
  input Connect.Set inSet;
  output Connect.Sets outCS;
  
  list<Connect.Set> sl;
  list<DAE.ComponentRef> c, d;
  list<Connect.OuterConnect> o;
  list<Connect.StreamFlowConnect> sf;
algorithm
  Connect.SETS(sl, c, d, o, sf) := inCS;
  outCS := Connect.SETS(inSet :: sl, c, d, o, sf);
end addConnectSet;

public function setOuterConnects
  "Sets the outer connect part of a Connect.Sets."
  input Connect.Sets inCS;
  input list<Connect.OuterConnect> inOuterConnects;
  output Connect.Sets outCS;

  list<Connect.Set> sl;
  list<DAE.ComponentRef> c, d;
  list<Connect.StreamFlowConnect> sf;
algorithm
  Connect.SETS(sl, c, d, _, sf) := inCS;
  outCS := Connect.SETS(sl, c, d, inOuterConnects, sf);
end setOuterConnects;

public function addOuterConnect
  "Adds an outer connect to a Connect.Sets."
  input Connect.Sets inCS;
  input Connect.OuterConnect inOuterConnect;
  output Connect.Sets outCS;

  list<Connect.Set> sl;
  list<DAE.ComponentRef> c, d;
  list<Connect.OuterConnect> o;
  list<Connect.StreamFlowConnect> sf;
algorithm
  Connect.SETS(sl, c, d, o, sf) := inCS;
  outCS := Connect.SETS(sl, c, d, inOuterConnect :: o, sf);
end addOuterConnect;

public function setConnectionCrefs
  "Sets the connection part of a Connect.Sets."
  input Connect.Sets inCS;
  input list<DAE.ComponentRef> inConnectionCrefs;
  output Connect.Sets outCS;

  list<Connect.Set> sl;
  list<DAE.ComponentRef> d;
  list<Connect.OuterConnect> o;
  list<Connect.StreamFlowConnect> sf;
algorithm
  Connect.SETS(sl, _, d, o, sf) := inCS;
  outCS := Connect.SETS(sl, inConnectionCrefs, d, o, sf);
end setConnectionCrefs;

public function addConnectionCrefs
  "Adds a list of connection crefs to a Connect.Sets."
  input Connect.Sets inCS;
  input list<DAE.ComponentRef> inConnectionCrefs;
  output Connect.Sets outCS;

  list<Connect.Set> sl;
  list<DAE.ComponentRef> c, d;
  list<Connect.OuterConnect> o;
  list<Connect.StreamFlowConnect> sf;
algorithm
  Connect.SETS(sl, c, d, o, sf) := inCS;
  c := listAppend(inConnectionCrefs, c);
  outCS := Connect.SETS(sl, c, d, o, sf);
end addConnectionCrefs;

public function addDeletedComponent
  "Adds a conditional component with condition = false to the connection sets,
  so that we can avoid adding connections to those components."
  input DAE.ComponentRef component;
  input Connect.Sets inSets;
  output Connect.Sets outSets;

  list<Connect.Set> sl;
  list<DAE.ComponentRef> c, d;
  list<Connect.OuterConnect> o;
  list<Connect.StreamFlowConnect> sf;
algorithm
  Connect.SETS(sl, c, d, o, sf) := inSets;
  outSets := Connect.SETS(sl, c, component :: d, o, sf);
end addDeletedComponent;

protected function isDeletedComponent
  "Checks if a component is a conditional component with condition = false."
  input DAE.ComponentRef component;
  input list<DAE.ComponentRef> deletedComponents;
  output Boolean isDeleted;
algorithm
  isDeleted := matchcontinue(component, deletedComponents)
    local
      DAE.ComponentRef c;
      list<DAE.ComponentRef> rest;
      Boolean is_deleted;
    case (_, {}) then false;
    case (_, c :: _)
      equation
        true = ComponentReference.crefPrefixOf(c, component);
      then
        true;
    case (_, _ :: rest)
      equation
        is_deleted = isDeletedComponent(component, rest);
      then
        is_deleted;
  end matchcontinue;
end isDeletedComponent;

public function connectionContainsDeletedComponents
  "Checks if a connection contains any conditional components with condition =
  false."
  input DAE.ComponentRef component1;
  input DAE.ComponentRef component2;
  input Connect.Sets sets;
  output Boolean containsDeletedComponent;
algorithm
  containsDeletedComponent := matchcontinue(component1, component2, sets)
    local
      list<DAE.ComponentRef> dc;
    // No components have been deleted.
    case (_, _, Connect.SETS(deletedComponents = {})) then false;
    // The first component is deleted.
    case (_, _, Connect.SETS(deletedComponents = dc))
      equation
        true = isDeletedComponent(component1, dc);
      then
        true;
    // The second component is deleted;
    case (_, _, Connect.SETS(deletedComponents = dc))
      equation
        true = isDeletedComponent(component2, dc);
      then
        true;
    // Neither of the components are deleted.
    case (_, _, _) then false;
  end matchcontinue;
end connectionContainsDeletedComponents;
    
public function addOuterConnection " Adds a connection with a reference to an outer connector
These are added to a special list, such that they can be moved up in the instance hierarchy to a place
where both instances are defined."
  input Prefix.Prefix scope;
  input Connect.Sets sets;
  input DAE.ComponentRef cr1;
  input DAE.ComponentRef cr2;
  input Absyn.InnerOuter io1;
  input Absyn.InnerOuter io2;
  input Connect.Face f1;
  input Connect.Face f2;
  input DAE.ElementSource source;
  output Connect.Sets outSets;
algorithm
  outSets := matchcontinue(scope,sets,cr1,cr2,io1,io2,f1,f2,source)
    local
      list<Connect.Set> ss;
      list<DAE.ComponentRef> crs,dc;
      list<Connect.OuterConnect> oc;
      Connect.OuterConnect new_oc;
    // First check if already added
    case(scope, Connect.SETS(outerConnects = oc),cr1,cr2,io1,io2,f1,f2,_)
      equation
        _::_ = Util.listSelect2(oc,cr1,cr2,outerConnectionMatches);
      then sets;
    // add the outerconnect
    case(scope,_,cr1,cr2,io1,io2,f1,f2,source)
      equation
        new_oc = Connect.OUTERCONNECT(scope, cr1, io1, f1, cr2, io2, f2, source);
      then addOuterConnect(sets, new_oc);
  end matchcontinue;
end addOuterConnection;

protected function outerConnectionMatches "Returns true if Connect.OuterConnect matches the two component refernces passed as argument"
  input Connect.OuterConnect oc;
  input DAE.ComponentRef cr1;
  input DAE.ComponentRef cr2;
  output Boolean matches;
algorithm
  matches := matchcontinue(oc,cr1,cr2)
    local DAE.ComponentRef cr11,cr22;
    case(Connect.OUTERCONNECT(cr1=cr11,cr2=cr22),cr1,cr2) 
      equation
        matches =
        ComponentReference.crefEqual(cr11,cr1) and ComponentReference.crefEqual(cr22,cr2) or
        ComponentReference.crefEqual(cr11,cr2) and ComponentReference.crefEqual(cr22,cr1);
      then matches;
  end matchcontinue;
end outerConnectionMatches;

public function addOuterConnectToSets "adds an outerconnection to all sets where a corresponding inner definition is present
For instance,
if a connection set contains {world.v, topPin.v}
and we have an outer connection connect(world,a2.aPin),
the connection should be added to the set, resulting in
{world.v,topPin.v,a2.aPin.v}"
  input DAE.ComponentRef cr1;
  input DAE.ComponentRef cr2;
  input Absyn.InnerOuter io1;
  input Absyn.InnerOuter io2;
  input Connect.Face f1;
  input Connect.Face f2;
  input list<Connect.Set> setLst;
  input list<DAE.ComponentRef> inCrs;
  output list<Connect.Set> outSetLst;
  output list<DAE.ComponentRef> outCrs;
  output Boolean added "true if addition was made";
algorithm
  (outSetLst,outCrs,added) := matchcontinue(cr1,cr2,io1,io2,f1,f2,setLst,inCrs)
  local
    list<Connect.EquSetElement> crs;
    list<Connect.FlowSetElement> fcrs;
    list<Connect.StreamSetElement> scrs;
    Connect.Set set; Boolean added2;

    case(cr1,cr2,io1,io2,f1,f2,{},inCrs) then ({},inCrs,false);

    case(cr1,cr2,io1,io2,f1,f2,Connect.EQU(crs)::setLst,inCrs) equation
      (crs,inCrs,added) = addOuterConnectToSets2(cr1,cr2,io1,io2,crs,inCrs);
      (setLst,inCrs,added2) = addOuterConnectToSets(cr1,cr2,io1,io2,f1,f2,setLst,inCrs);
    then (Connect.EQU(crs)::setLst,inCrs,added or added2);

    case(cr1,cr2,io1,io2,f1,f2,Connect.FLOW(fcrs as _ :: _ :: _)::setLst,inCrs) equation
      (fcrs,inCrs,setLst,added) = addOuterConnectToSets3(cr1,cr2,f1,f2,io1,io2,fcrs,inCrs,setLst);
      (setLst,inCrs,added2) = addOuterConnectToSets(cr1,cr2,io1,io2,f1,f2,setLst,inCrs);
    then (Connect.FLOW(fcrs)::setLst,inCrs,added or added2);

    case(cr1,cr2,io1,io2,f1,f2,Connect.STREAM(scrs)::setLst,inCrs) equation
      (scrs,inCrs,added) = addOuterConnectToSets4(cr1,cr2,f1,f2,io1,io2,scrs,inCrs);
      (setLst,inCrs,added2) = addOuterConnectToSets(cr1,cr2,io1,io2,f1,f2,setLst,inCrs);
    then (Connect.STREAM(scrs)::setLst,inCrs,added or added2);

    case(cr1,cr2,io1,io2,f1,f2,set::setLst,inCrs) equation
      (setLst,inCrs,added) = addOuterConnectToSets(cr1,cr2,io1,io2,f1,f2,setLst,inCrs);
    then (set::setLst,inCrs,added);
  end matchcontinue;
end addOuterConnectToSets;

protected function addOuterConnectToSets2 "help function to addOuterconnectToSets"
  input DAE.ComponentRef cr1;
  input DAE.ComponentRef cr2;
  input Absyn.InnerOuter io1;
  input Absyn.InnerOuter io2;
  input list<Connect.EquSetElement> crs;
  input list<DAE.ComponentRef> inCrs "from connection crefs (outer scopes)";
  output list<Connect.EquSetElement> outCrs;
  output list<DAE.ComponentRef> outCrs2 "from connection crefs (outer scopes)";
  output Boolean added;
protected
  Boolean isOuter1,isOuter2;
algorithm
  (_,isOuter1) := InnerOuter.innerOuterBooleans(io1);
  (_,isOuter2) := InnerOuter.innerOuterBooleans(io2);
  (outCrs,outCrs2,added) := addOuterConnectToSets22(cr1,cr2,isOuter1,isOuter2,crs,inCrs);
end addOuterConnectToSets2;

protected function addOuterConnectToSets22 "help function to addOuterconnectToSets2"
  input DAE.ComponentRef cr1;
  input DAE.ComponentRef cr2;
  input Boolean isOuter1;
  input Boolean isOuter2;
  input list<Connect.EquSetElement> crs;
  input list<DAE.ComponentRef> inCrs "from connection crefs (outer scopes)";
  output list<Connect.EquSetElement> outCrs;
  output list<DAE.ComponentRef> outCrs2 "from connection crefs (outer scopes)";
  output Boolean added;
algorithm
  (outCrs,outCrs2,added) := matchcontinue(cr1,cr2,isOuter1,isOuter2,crs,inCrs)
    local
      DAE.ComponentRef outerCr,connectorCr,newCr;
      DAE.ElementSource src;

    case(cr1,cr2,true,true,crs,inCrs)
      equation
        Error.addMessage(Error.UNSUPPORTED_LANGUAGE_FEATURE,{"Connections where both connectors are outer references","No suggestion"});
      then (crs,inCrs,false);

    case(cr1,cr2,true,false,crs,inCrs)
      equation
        (outerCr,src)::_ = Util.listSelect1(crs,cr1,crefTuplePrefixOf);
        connectorCr = ComponentReference.crefStripPrefix(outerCr,cr1);
        newCr = ComponentReference.joinCrefs(cr2,connectorCr);
      then ((newCr,src)::crs,inCrs,true);

    case(cr1,cr2,false,true,crs,inCrs)
      equation
        (outerCr,src)::_ = Util.listSelect1(crs,cr2,crefTuplePrefixOf);
        connectorCr = ComponentReference.crefStripPrefix(outerCr,cr2);
        newCr = ComponentReference.joinCrefs(cr1,connectorCr);
      then ((newCr,src)::crs,inCrs,true);

    case(cr1,cr2,_,_,crs,inCrs) then (crs,inCrs,false);
  end matchcontinue;
end addOuterConnectToSets22;

protected function addOuterConnectToSets3 "help function to addOuterconnectToSets"
  input DAE.ComponentRef cr1;
  input DAE.ComponentRef cr2;
  input Connect.Face f1;
  input Connect.Face f2;
  input Absyn.InnerOuter io1;
  input Absyn.InnerOuter io2;
  input list<Connect.FlowSetElement> crs;
  input list<DAE.ComponentRef> inCrs;
  input list<Connect.Set> inSets;
  output list<Connect.FlowSetElement> outCrs;
  output list<DAE.ComponentRef> outCrs2;
  output list<Connect.Set> outSets;
  output Boolean added;
protected
  Boolean isOuter1,isOuter2;
algorithm
  (_,isOuter1) := InnerOuter.innerOuterBooleans(io1);
  (_,isOuter2) := InnerOuter.innerOuterBooleans(io2);
  (outCrs,outCrs2,outSets,added) := addOuterConnectToSets33(cr1,cr2,isOuter1,isOuter2,f1,f2,crs,inCrs,inSets);
end addOuterConnectToSets3;

protected function addOuterConnectToSets33 "help function to addOuterconnectToSets3"
  input DAE.ComponentRef cr1;
  input DAE.ComponentRef cr2;
  input Boolean isOuter1;
  input Boolean isOuter2;
  input Connect.Face f1;
  input Connect.Face f2;
  input list<Connect.FlowSetElement> crs;
  input list<DAE.ComponentRef> inCrs;
  input list<Connect.Set> inSets;
  output list<Connect.FlowSetElement> outCrs;
  output list<DAE.ComponentRef> outCrs2;
  output list<Connect.Set> outSets;
  output Boolean added;
algorithm
  (outCrs,outCrs2,outSets,added) := matchcontinue(cr1,cr2,isOuter1,isOuter2,f1,f2,crs,inCrs,inSets)
    local
      DAE.ComponentRef outerCr,connectorCr,newCr;
      DAE.ElementSource src;
      list<Connect.Set> sets;

    case(cr1,cr2,true,true,f1,f2,crs,inCrs,_)
      equation
        Error.addMessage(Error.UNSUPPORTED_LANGUAGE_FEATURE,{"Connections where both connectors are outer references","No suggestion"});
      then (crs,inCrs,inSets,false);

    case(cr1,cr2,true,false,f1,f2,crs,inCrs,_)
      equation
        (outerCr,_,src)::_ = Util.listSelect1(crs,cr1,flowTuplePrefixOf);
        connectorCr = ComponentReference.crefStripPrefix(outerCr,cr1);
        newCr = ComponentReference.joinCrefs(cr2,connectorCr);
        sets = removeUnconnectedFlowVariable(newCr, f2, inSets);
      then ((newCr,f2,src)::crs,inCrs,sets,true);

    case(cr1,cr2,false,true,f1,f2,crs,inCrs,_)
      equation
        (outerCr,_,src)::_ = Util.listSelect1(crs,cr2,flowTuplePrefixOf);
        connectorCr = ComponentReference.crefStripPrefix(outerCr,cr2);
        newCr = ComponentReference.joinCrefs(cr1,connectorCr);
        sets = removeUnconnectedFlowVariable(newCr, f1, inSets);
      then ((newCr,f1,src)::crs,inCrs,sets,true);

    case(cr1,cr2,_,_,_,_,crs,inCrs,_) then (crs,inCrs,inSets,false);
  end matchcontinue;
end addOuterConnectToSets33;

protected function addOuterConnectToSets4 "help function to addOuterconnectToSets"
  input DAE.ComponentRef cr1;
  input DAE.ComponentRef cr2;
  input Connect.Face f1;
  input Connect.Face f2;
  input Absyn.InnerOuter io1;
  input Absyn.InnerOuter io2;
  input list<Connect.StreamSetElement> crs;
  input list<DAE.ComponentRef> inCrs;
  output list<Connect.StreamSetElement> outCrs;
  output list<DAE.ComponentRef> outCrs2;
  output Boolean added;
protected
  Boolean isOuter1,isOuter2;
algorithm
  (_,isOuter1) := InnerOuter.innerOuterBooleans(io1);
  (_,isOuter2) := InnerOuter.innerOuterBooleans(io2);
  (outCrs,outCrs2,added) := addOuterConnectToSets44(cr1,cr2,isOuter1,isOuter2,f1,f2,crs,inCrs);
end addOuterConnectToSets4;

protected function addOuterConnectToSets44 "help function to addOuterconnectToSets4"
  input DAE.ComponentRef cr1;
  input DAE.ComponentRef cr2;
  input Boolean isOuter1;
  input Boolean isOuter2;
  input Connect.Face f1;
  input Connect.Face f2;
  input list<Connect.StreamSetElement> crs;
  input list<DAE.ComponentRef> inCrs;
  output list<Connect.StreamSetElement> outCrs;
  output list<DAE.ComponentRef> outCrs2;
  output Boolean added;
algorithm
  (outCrs,outCrs2,added) := matchcontinue(cr1,cr2,isOuter1,isOuter2,f1,f2,crs,inCrs)
    local
      DAE.ComponentRef outerCr,connectorCr,newCr, outerCrFlow;
      DAE.ElementSource src;

    case(cr1,cr2,true,true,f1,f2,crs,inCrs)
      equation
        Error.addMessage(Error.UNSUPPORTED_LANGUAGE_FEATURE,{"Connections where both connectors are outer references","No suggestion"});
      then (crs,inCrs,false);

    case(cr1,cr2,true,false,f1,f2,crs,inCrs)
      equation
        (outerCr,outerCrFlow,_,src)::_ = Util.listSelect1(crs,cr1,streamTuplePrefixOf);
        connectorCr = ComponentReference.crefStripPrefix(outerCr,cr1);
        newCr = ComponentReference.joinCrefs(cr2,connectorCr);        
      then ((newCr,outerCrFlow,f2,src)::crs,inCrs,true);

    case(cr1,cr2,false,true,f1,f2,crs,inCrs)
      equation
        (outerCr,outerCrFlow,_,src)::_ = Util.listSelect1(crs,cr2,streamTuplePrefixOf);
        connectorCr = ComponentReference.crefStripPrefix(outerCr,cr2);
        newCr = ComponentReference.joinCrefs(cr1,connectorCr);
      then ((newCr,outerCrFlow,f1,src)::crs,inCrs,true);

    case(cr1,cr2,_,_,_,_,crs,inCrs) then (crs,inCrs,false);
  end matchcontinue;
end addOuterConnectToSets44;

public function addEqu "function: addEqu
  Adds an equal equation, see explaining text above.
  - Adding
  The two functions addEq and addFlow addes a variable to a
  connection set.  The first function is used to add a non-flow
  variable, and the second is used to add a flow variable.  When
  two component are to be added to a collection of connection sets,
  the connections sets containg the components have to be located.
  If no such set exists, a new set containing only the new component
  is created.

  If the connection sets containing the two components are not the
  same, they are merged."
  input Connect.Sets ss;
  input DAE.ComponentRef r1;
  input DAE.ComponentRef r2;
  input DAE.ElementSource source "the origin of the element";
  output Connect.Sets ss_1;
  Connect.Set s1,s2;
algorithm
  s1 := findEquSet(ss, r1, source);
  s2 := findEquSet(ss, r2, source);
  
  ss_1 := merge(ss, s1, s2);
end addEqu;

public function addFlow "function: addFlow
  Adds an flow equation, see addEqu above."
  input Connect.Sets ss;
  input DAE.ComponentRef r1;
  input Connect.Face d1;
  input DAE.ComponentRef r2;
  input Connect.Face d2;
  input DAE.ElementSource source "the element origin";
  output Connect.Sets ss_1;
  Connect.Set s1,s2;
algorithm
  s1 := findFlowSet(ss, r1, d1, source);
  s2 := findFlowSet(ss, r2, d2, source);
  ss_1 := merge(ss, s1, s2);
end addFlow;

public function addArrayFlow "function: addArrayFlow
 For connecting two arrays, a flow equation for each index should be generated, see addFlow."
  input Connect.Sets ss;
  input DAE.ComponentRef r1;
  input Connect.Face d1;
  input DAE.ComponentRef r2;
  input Connect.Face d2;
  input Integer dsize;
  input DAE.ElementSource source "the element origin";
  output Connect.Sets outSets;
  Connect.Set s1,s2;
  Connect.Sets ss_1;
algorithm
  outSets := matchcontinue (ss,r1,d1,r2,d2,dsize,source)
    local
      Connect.Sets s,ss_1,ss_2;
      DAE.ComponentRef r1_1,r2_1;
      Integer i_1,i;
      Connect.Set s1,s2;

    case (s,_,_,_,_,0,source) then s;
    case (ss,r1,d1,r2,d2,i,source)
      equation
        r1_1 = ComponentReference.subscriptCref(r1, {DAE.INDEX(DAE.ICONST(i))});
        r2_1 = ComponentReference.subscriptCref(r2, {DAE.INDEX(DAE.ICONST(i))});
        i_1 = i - 1;
        s1 = findFlowSet(ss, r1_1, d1, source);
        s2 = findFlowSet(ss, r2_1, d2, source);
        ss_1 = merge(ss, s1, s2);
        ss_2 = addArrayFlow(ss_1, r1, d1, r2, d2, i_1, source);
      then
        ss_2;
  end matchcontinue;
end addArrayFlow;

public function addFlowVariable
  "Adds a single flow variable to the connection sets."
  input Connect.Sets inCS;
  input DAE.ComponentRef inCref;
  input Connect.Face inFace;
  input DAE.ElementSource inSource;
  output Connect.Sets outCS;
algorithm
  outCS := matchcontinue(inCS, inCref, inFace, inSource)
    local
      list<Connect.Set> sl;
      Connect.Set flow_set;
    
    // If the variable has already been added, do nothing.
    case (Connect.SETS(setLst = sl as _ :: _), _, _, _)
      equation
        failure(_ = Util.listMap2(sl, checkSet, inCref, inFace));
      then
        inCS;

    // Otherwise, create a new flow set and add it to the sets.
    else
      equation
        flow_set = newFlowSet(inCref, inFace, inSource);
      then
        addConnectSet(inCS, flow_set);
  end matchcontinue;
end addFlowVariable;

public function checkSet
  "Checks that a given component is not a member of the given set. If the
  component is in the set it fails."
  input Connect.Set inSet;
  input DAE.ComponentRef inComponentRef;
  input Connect.Face inFace;
  output Connect.Set outSet;
algorithm
  outSet := matchcontinue(inSet, inComponentRef, inFace)
    local 
      list<Connect.FlowSetElement> cs;  
    
    case (Connect.FLOW(tplExpComponentRefFaceLst = cs), _, _)
      equation
        failure(findInSetFlow(cs, inComponentRef, inFace));
      then
        inSet;
    
    case (Connect.EQU(expComponentRefLst = _), _, _) then inSet;
    
    case (Connect.STREAM(tplExpComponentRefFaceLst = _), _, _) then inSet;
  end matchcontinue;
end checkSet;

public function addStreamFlowAssociation
  "Adds an association between a stream variable and a flow."
  input DAE.ComponentRef inStreamCref;
  input DAE.ComponentRef inFlowCref;
  input Connect.Sets inSets;
  output Connect.Sets outSets;

  list<Connect.Set> sl;
  list<DAE.ComponentRef> c, d;
  list<Connect.OuterConnect> o;
  list<Connect.StreamFlowConnect> sf;
algorithm
  outSets := matchcontinue(inStreamCref, inFlowCref, inSets)

    // Association already added.
    case (_, _, _)
      equation
        _ = getStreamFlowAssociation(inStreamCref, inSets);
      then
        inSets;

    // Add a new association.
    case (_, _, Connect.SETS(sl, c, d, o, sf))
      then Connect.SETS(sl, c, d, o, (inStreamCref, inFlowCref) :: sf);
  end matchcontinue;
end addStreamFlowAssociation;

public function getStreamFlowAssociation
  "Returns the flow variable that is associated with a stream varible, or
  fails."
  input DAE.ComponentRef inStreamCref;
  input Connect.Sets inSets;
  output DAE.ComponentRef outFlowCref;

  list<Connect.StreamFlowConnect> sf;
algorithm
  Connect.SETS(streamFlowConnects = sf) := inSets;
  ((_, outFlowCref)) := Util.listGetMemberOnTrue(inStreamCref, sf,
    streamFlowConnectEqual);
end getStreamFlowAssociation;

protected function streamFlowConnectEqual
  "Helper function to getStreamFlowAssociation, checks if the stream cref
  matches the cref in the StreamFlowConnect tuple."
  input DAE.ComponentRef inStreamCref;
  input Connect.StreamFlowConnect inStreamFlowConnect;
  output Boolean isEqual;

  DAE.ComponentRef stream_cr;
algorithm
  (stream_cr, _) := inStreamFlowConnect;
  isEqual := ComponentReference.crefEqualNoStringCompare(stream_cr, inStreamCref);
end streamFlowConnectEqual;

public function addStream "function: addStream
  Adds an stream equation, see addEqu above."
  input Connect.Sets ss;
  input DAE.ComponentRef r1;
  input Connect.Face d1;
  input DAE.ComponentRef r2;
  input Connect.Face d2;
  input DAE.ElementSource source "the element origin";
  output Connect.Sets ss_1;

  Connect.Set s1,s2;
  DAE.ComponentRef f1, f2;
algorithm
  f1 := getStreamFlowAssociation(r1, ss);
  f2 := getStreamFlowAssociation(r2, ss);
  s1 := findStreamSet(ss, r1, f1, d1, source);
  s2 := findStreamSet(ss, r2, f2, d2, source);
  ss_1 := merge(ss, s1, s2);
end addStream;

public function addArrayStream "function: addArrayStream
 For connecting two arrays, a flow equation for each index should be generated, see addStream."
  input Connect.Sets ss;
  input DAE.ComponentRef r1;
  input Connect.Face d1;
  input DAE.ComponentRef r2;
  input Connect.Face d2;
  input Integer dsize;
  input DAE.ElementSource source "the element origin";
  output Connect.Sets outSets;
algorithm
  outSets := matchcontinue (ss,r1,d1,r2,d2,dsize,source)
    local
      Connect.Sets s,ss_1,ss_2;
      DAE.ComponentRef r1_1,r2_1;
      Integer i_1,i;
      Connect.Set s1,s2;

    case (s,_,_,_,_,0,source) then s;
    case (ss,r1,d1,r2,d2,i,source)
      equation
        r1_1 = ComponentReference.subscriptCref(r1, {DAE.INDEX(DAE.ICONST(i))});
        r2_1 = ComponentReference.subscriptCref(r2, {DAE.INDEX(DAE.ICONST(i))});
        i_1 = i - 1;
        ss_1 = addStream(ss, r1_1, d1, r2_1, d2, source);
        ss_2 = addArrayStream(ss_1, r1, d1, r2, d2, i_1, source);
      then
        ss_2;
  end matchcontinue;
end addArrayStream;

public function addMultiArrayEqu "function: addMultiArrayEqu
 Author: BZ 2008-07
  For connecting two arrays, an equal equation for each index should
  be generated. generic dimensionality"
  input Connect.Sets inSets1;
  input DAE.ComponentRef inComponentRef2;
  input DAE.ComponentRef inComponentRef3;
  input list<DAE.Dimension> dimensions;
  input DAE.ElementSource source "the origins of the element";
  output Connect.Sets outSets;
algorithm
  outSets := matchcontinue (inSets1,inComponentRef2,inComponentRef3,dimensions,source)
    local
      list<list<DAE.Exp>> expSubs;
      list<list<DAE.Subscript>> subSubs;
      Integer dimension;
    case (inSets1,_,_,{},source) then inSets1;
    case (inSets1,inComponentRef2,inComponentRef3,dimensions,source)
      equation
        expSubs = generateSubscriptList(dimensions);
        subSubs = Util.listListMap(expSubs,Expression.makeIndexSubscript);
        outSets = addMultiArrayEqu2(inSets1,inComponentRef2,inComponentRef3,subSubs,source);
      then
       outSets;
  end matchcontinue;
end addMultiArrayEqu;

protected function addMultiArrayEqu2 "
Author: BZ, 2008-07
Generates Subscripts, from the input list<list, for the componentreferences given."
  input Connect.Sets inSets1;
  input DAE.ComponentRef inComponentRef2;
  input DAE.ComponentRef inComponentRef3;
  input list<list<DAE.Subscript>> dimensions;
  input DAE.ElementSource source "the origins of the element";
  output Connect.Sets outSets;
algorithm
  outSets := matchcontinue(inSets1,inComponentRef2,inComponentRef3,dimensions,source)
    local
      Connect.Sets s,ss_1,ss_2,ss;
      DAE.ComponentRef r1_1,r2_1,r1,r2;
      Connect.Set s1,s2;
      list<list<DAE.Subscript>> restDims;
      list<DAE.Subscript> dims;
      Integer dimension;
    case (s,_,_,{},_) then s;
    case (ss,r1,r2,dims::restDims,source)
      equation
        r1_1 = ComponentReference.replaceCrefSliceSub(r1,dims);
        r2_1 = ComponentReference.replaceCrefSliceSub(r2,dims);
        s1 = findEquSet(ss, r1_1, source);
        s2 = findEquSet(ss, r2_1, source);
        ss_1 = merge(ss, s1, s2);
        ss_2 = addMultiArrayEqu2(ss_1, r1, r2, restDims, source);
      then
        ss_2;
  end matchcontinue;
end addMultiArrayEqu2;

protected function generateSubscriptList "
Author BZ 2008-07
Generates all subscripts for the dimension/(s)"
  input list<DAE.Dimension> dims;
  output list<list<DAE.Exp>> subs;
algorithm subs := matchcontinue(dims)
  local
    DAE.Dimension dim;
    list<DAE.Dimension> rest;
    list<list<DAE.Exp>> nextLevel,result,currLevel;
  case(dim::{})
    equation
      currLevel = generateSubscriptList2(dim);
      currLevel = listReverse(currLevel);
    then currLevel;
  case(dim::rest)
    equation
      currLevel = generateSubscriptList2(dim);
      currLevel = listReverse(currLevel);
      nextLevel = generateSubscriptList(rest);
      result = mergeCurrentWithRestIndexies(nextLevel,currLevel);
    then result;
end matchcontinue;
end generateSubscriptList;

protected function generateSubscriptList2
  input DAE.Dimension inDim;
  output list<list<DAE.Exp>> outIndices;
algorithm
  outIndices := matchcontinue(inDim)
    local
      list<DAE.Exp> exp_indices;
      list<list<DAE.Exp>> res;
      Integer i;
      list<Integer> indices;
      Absyn.Path name;
      list<String> l;
      list<DAE.Exp> el;
    
    case DAE.DIM_INTEGER(integer = i)
      equation
        indices = Util.listIntRange(i);
        res = Util.listMap(Util.listMap(indices, Expression.makeIntegerExp), Util.listCreate);
      then
        res;
    
    case DAE.DIM_ENUM(enumTypeName = name, literals = l)
      equation
        (DAE.ARRAY(array = el), _) = Static.makeEnumerationArray(name, l);
        res = Util.listMap(el, Util.listCreate);
      then
        res;
  end matchcontinue;
end generateSubscriptList2;

protected function mergeCurrentWithRestIndexies "
Helper function for generateSubscriptList, merges recursive dimensions with current."
  input list<list<DAE.Exp>> curr;
  input list<list<DAE.Exp>> Indexies;
  output list<list<DAE.Exp>> oIndexies;
algorithm 
  oIndexies := matchcontinue(curr,Indexies)
    local
      list<DAE.Exp> il;
      list<list<DAE.Exp>> ill,merged;
  
    case(_,{}) then {};
  
    case(curr,(il as (_ :: (_ :: _)))::ill)
      equation
        ill = mergeCurrentWithRestIndexies(curr,ill);
        merged = Util.listMap1(curr,Util.listAppendr,il);
        merged = listAppend(merged,ill);
      then
        merged;
    
    case(curr,(il as {_})::ill)
      equation
        ill = mergeCurrentWithRestIndexies(curr,ill);
        merged = Util.listMap1(curr,Util.listAppendr,il);
        merged = listAppend(merged,ill);
      then
        merged;
  end matchcontinue;
end mergeCurrentWithRestIndexies;

protected function crefTupleNotPrefixOf
  "Determines if connection cref is prefix to the component "
  input Connect.EquSetElement tupleCrSource;
  input DAE.ComponentRef compName;
  output Boolean selected;
algorithm
  selected := matchcontinue(tupleCrSource,compName)
    local DAE.ComponentRef cr;
    case((cr,_),compName) then ComponentReference.crefNotPrefixOf(compName,cr);
  end matchcontinue;
end crefTupleNotPrefixOf;

protected function crefTuplePrefixOf
  "Determines if connection cref is NOT prefix to the component "
  input Connect.EquSetElement tupleCrSource;
  input DAE.ComponentRef compName;
  output Boolean selected;
algorithm
  selected := matchcontinue(tupleCrSource,compName)
    local DAE.ComponentRef cr;
    case((cr,_),compName) then ComponentReference.crefPrefixOf(compName,cr);
  end matchcontinue;
end crefTuplePrefixOf;

protected function flowTupleNotPrefixOf 
  "Determines if connection cref is NOT prefix to the component "
  input Connect.FlowSetElement tpl;
  input DAE.ComponentRef compName;
  output Boolean b;
algorithm
  b:= matchcontinue(tpl,compName)
    local DAE.ComponentRef cr;
    case((cr,_,_),compName) then ComponentReference.crefNotPrefixOf(compName,cr);
  end matchcontinue;
end flowTupleNotPrefixOf;

protected function flowTuplePrefixOf 
  "Determines if connection cref is prefix to the component "
  input Connect.FlowSetElement tpl;
  input DAE.ComponentRef compName;
  output Boolean b;
algorithm
  b:= matchcontinue(tpl,compName)
    local DAE.ComponentRef cr;
    case((cr,_,_),compName) then ComponentReference.crefPrefixOf(compName,cr);
  end matchcontinue;
end flowTuplePrefixOf;

protected function streamTupleNotPrefixOf 
  "Determines if connection cref is NOT prefix to the component "
  input Connect.StreamSetElement tpl;
  input DAE.ComponentRef compName;
  output Boolean b;
algorithm
  b:= matchcontinue(tpl,compName)
    local DAE.ComponentRef cr;
    case((cr,_,_,_),compName) then ComponentReference.crefNotPrefixOf(compName,cr);
  end matchcontinue;
end streamTupleNotPrefixOf;

protected function streamTuplePrefixOf 
  "Determines if connection cref is prefix to the component "
  input Connect.StreamSetElement tpl;
  input DAE.ComponentRef compName;
  output Boolean b;
algorithm
  b:= matchcontinue(tpl,compName)
    local DAE.ComponentRef cr;
    case((cr,_,_,_),compName) then ComponentReference.crefPrefixOf(compName,cr);
  end matchcontinue;
end streamTuplePrefixOf;

public function equations
  "From a number of connection sets, this function generates a list of
  equations."
  input Connect.Sets inSets;
  output DAE.DAElist outDae;
  
  list<Connect.Set> ss;
  list<DAE.DAElist> daes;
algorithm
  Connect.SETS(setLst = ss) := inSets;
  outDae := Util.listFold(ss, equations_dispatch, DAEUtil.emptyDae);
end equations;

public function equations_dispatch
  "Helper function to equations, calls the right equation generating function."
  input Connect.Set inSet;
  input DAE.DAElist inDae;
  output DAE.DAElist outDae;
algorithm
  outDae := matchcontinue(inSet, inDae)
    local
      list<Connect.EquSetElement> csEqu;
      list<Connect.FlowSetElement> csFlow;
      list<Connect.StreamSetElement> csStream;
      DAE.DAElist dae;

    // generate potential equations
    case (Connect.EQU(expComponentRefLst = csEqu), _)
      equation
        dae = equEquations(csEqu);
        dae = DAEUtil.joinDaes(inDae, dae);
      then
        dae;

    // generate flow equations
    case (Connect.FLOW(tplExpComponentRefFaceLst = csFlow), _)
      equation
        dae = flowEquations(csFlow);
        dae = DAEUtil.joinDaes(inDae, dae);
      then
        dae;

    // generate stream equations
    case (Connect.STREAM(tplExpComponentRefFaceLst = csStream), _)
      equation
        dae = streamEquations(csStream);
        dae = DAEUtil.joinDaes(inDae, dae);
      then
        dae;
        
    // failure
    else
      equation
        Debug.fprint("failtrace","- ConnectUtil.equations failed\n");
      then
        fail();
  end matchcontinue;
end equations_dispatch;

protected function equEquations "function: equEquations
  A non-flow connection set contains a number of components.
  Generating the equation from this set means equating all the
  components.  For n components, this will give n-1 equations.
  For example, if the set contains the components X, Y.A and
  Z.B, the equations generated will be X = Y.A and X = Z.B."
  input list<Connect.EquSetElement> inExpComponentRefLst;
  output DAE.DAElist outDae;
algorithm
  outDae := matchcontinue (inExpComponentRefLst)
    local
      list<DAE.Element> eq;
      DAE.ComponentRef x,y;
      list<Connect.EquSetElement> cs;
      DAE.ElementSource src,src1,src2;
      DAE.FunctionTree funcs;
      Absyn.Info info;
      list<Absyn.Within> partOfLst;
      list<Option<DAE.ComponentRef>> instanceOptLst;
      list<Option<tuple<DAE.ComponentRef, DAE.ComponentRef>>> connectEquationOptLst;
      list<Absyn.Path> typeLst;      

    case {_} then DAEUtil.emptyDae;
    
    case ((x,src1) :: ((y,src2) :: cs))
      equation
        DAE.DAE(eq) = equEquations(((x,src1) :: cs));
        DAE.SOURCE(info, partOfLst, instanceOptLst, connectEquationOptLst, typeLst) = DAEUtil.mergeSources(src1,src2);
        // do not propagate connects from different sources! use the crefs directly!
        src = DAE.SOURCE(info, partOfLst, instanceOptLst, {SOME((x,y))}, typeLst);
      then
        (DAE.DAE(DAE.EQUEQUATION(x,y,src) :: eq));
    
    case(_) equation print(" FAILURE IN CONNECT \n"); then fail();
  end matchcontinue;
end equEquations;

protected function flowEquations "function: flowEquations
  Generating equations from a flow connection set is a little
  trickier that from a non-flow set.  Only one equation is
  generated, but it has to consider whether the comoponents were
  inside or outside connectors.
  This function uses flowSum to create the sum of all components
  (some of which will be negated), and the returns the equation
  where this sum is equal to 0.0."
  input list<Connect.FlowSetElement> cs;
  output DAE.DAElist outDae;
  DAE.Exp sum;
  DAE.ElementSource source;
  list<DAE.ElementSource> lde;
  DAE.ElementSource ed;
  DAE.FunctionTree funcs;
algorithm
  sum := flowSum(cs);
  (ed::lde) := Util.listMap(cs, Util.tuple33);
  source := Util.listFold(lde, DAEUtil.mergeSources, ed);
  outDae := DAE.DAE({DAE.EQUATION(sum, DAE.RCONST(0.0), source)});
end flowEquations;

protected function flowSum "function: flowSum
  This function creates an exression expressing the sum of all
  components in the given list.  Before adding the component to the
  sum, it is passed to signFlow which will negate all outside
  connectors."
  input list<Connect.FlowSetElement> inTplExpComponentRefFaceLst;
  output DAE.Exp outExp;
algorithm
  outExp := matchcontinue (inTplExpComponentRefFaceLst)
    local
      DAE.Exp exp,exp1,exp2;
      DAE.ComponentRef c;
      Connect.Face f;
      list<Connect.FlowSetElement> cs;
    
    case {(c,f,_)}
      equation
        exp = signFlow(c, f);
         //print("Generating flow expression: " +& ExpressionDump.printExpStr(exp) +& "\n");
      then
        exp;
    
    case (((c,f,_) :: cs))
      equation
        exp1 = signFlow(c, f);
        exp2 = flowSum(cs);
      then
        DAE.BINARY(exp1,DAE.ADD(DAE.ET_REAL()),exp2);
  end matchcontinue;
end flowSum;

protected function signFlow "function: signFlow
  This function takes a name of a component and a Connect.Face, returns an
  expression. If the face is Connect.INSIDE the expression simply contains
  the component reference, but if it is Connect.OUTSIDE, the expression is
  negated."
  input DAE.ComponentRef inComponentRef;
  input Connect.Face inFace;
  output DAE.Exp outExp;
algorithm
  outExp := matchcontinue (inComponentRef,inFace)
    local DAE.ComponentRef c;
    case (c,Connect.INSIDE()) then DAE.CREF(c,DAE.ET_OTHER());
    case (c,Connect.OUTSIDE()) then DAE.UNARY(DAE.UMINUS(DAE.ET_REAL()),DAE.CREF(c,DAE.ET_OTHER()));
  end matchcontinue;
end signFlow;

protected function streamEquations "function: streamEquations
  Generating equations from a stream connection set is a little
  trickier that from a non-stream set."
  input list<Connect.StreamSetElement> cs;
  output DAE.DAElist outDae;
algorithm
  outDae := match(cs)
    local
      DAE.ComponentRef cr1, cr2;
      DAE.ElementSource src1, src2, src;
      DAE.FunctionTree funcs;
      DAE.DAElist dae;
      String str;
      list<String> strs;
      Connect.Face f1, f2;
      DAE.Exp cref1, cref2, e1, e2;
      list<Connect.StreamSetElement> inside, outside;

    // Unconnected stream connector, do nothing!
    case ({(_, _, Connect.INSIDE(), _)})
      then DAEUtil.emptyDae;

    // Both inside, do nothing!
    case ({(cr1, _, Connect.INSIDE(), _), (cr2, _, Connect.INSIDE(), _)})
      then DAEUtil.emptyDae;

    // Both outside:
    // cr1 = inStream(cr2);
    // cr2 = inStream(cr2);
    case ({(cr1, _, Connect.OUTSIDE(), src1), (cr2, _, Connect.OUTSIDE(), src2)})
      equation
        cref1 = Expression.crefExp(cr1);
        cref2 = Expression.crefExp(cr2);
        e1 = makeInStreamCall(cref2);
        e2 = makeInStreamCall(cref1);
        src = DAEUtil.mergeSources(src1, src2);
        dae = DAE.DAE({
          DAE.EQUATION(cref1, e1, src),
          DAE.EQUATION(cref2, e2, src)});
      then
        dae;

    // One inside, one outside:
    // cr1 = cr2;
    case ({(cr1, _, f1, src1), (cr2, _, f2, src2)}) 
      equation
        src = DAEUtil.mergeSources(src1, src2);
        dae = DAE.DAE({
                DAE.EQUATION(DAE.CREF(cr1,DAE.ET_OTHER()), 
                             DAE.CREF(cr2,DAE.ET_OTHER()), 
                             src)});
      then dae;

    // The general case with N inside connectors and M outside:
    case (_)
      equation
        (outside, inside) = Util.listSplitOnTrue(cs, isOutsideStream);
        dae = Util.listFold_3(outside, streamEquationGeneral, DAEUtil.emptyDae,
          outside, inside);
      then
        dae;
  end match;   
end streamEquations;

protected function isOutsideStream
  "Returns true of the stream set element is an outside connector."
  input Connect.StreamSetElement inElement;
  output Boolean isOutside;
algorithm
  isOutside := match(inElement)
    case ((_, _, Connect.OUTSIDE(), _)) then true;
    else then false;
  end match;
end isOutsideStream;

protected function streamEquationGeneral
  "Generates an equation for an outside stream connector."
  input DAE.DAElist inDae;
  input Connect.StreamSetElement inElement;
  input list<Connect.StreamSetElement> inOutsideElements;
  input list<Connect.StreamSetElement> inInsideElements;
  output DAE.DAElist outDae;

  list<Connect.StreamSetElement> outside;
  DAE.ComponentRef stream_cr;
  DAE.Exp cref_exp, outside_sum1, outside_sum2, inside_sum1, inside_sum2, res;
  DAE.ElementSource src;
  DAE.DAElist dae;
algorithm
  (stream_cr, _, _, src) := inElement;
  cref_exp := Expression.crefExp(stream_cr);
  outside := removeStreamSetElement(stream_cr, inOutsideElements);
  res := streamSumEquationExp(outside, inInsideElements);
  dae := DAE.DAE({DAE.EQUATION(cref_exp, res, src)});
  outDae := DAEUtil.joinDaes(dae, inDae);
end streamEquationGeneral;

protected function streamSumEquationExp
  "Generates the sum expression used by stream connector equations, given M
  outside connectors and N inside connectors:

    (sum(max(-flow_exp[i], eps) * stream_exp[i] for i in N) +
     sum(max( flow_exp[i], eps) * inStream(stream_exp[i]) for i in M)) /
    (sum(max(-flow_exp[i], eps) for i in N) +
     sum(max( flow_exp[i], eps) for i in M))
  "
  input list<Connect.StreamSetElement> inOutsideElements;
  input list<Connect.StreamSetElement> inInsideElements;
  output DAE.Exp outSumExp;

  DAE.Exp outside_sum1, outside_sum2, inside_sum1, inside_sum2, res;
algorithm
  outSumExp := match(inOutsideElements, inInsideElements)
    // No outside components.
    case ({}, _)
      equation
        inside_sum1 = sumMap(inInsideElements, sumInside1);
        inside_sum2 = sumMap(inInsideElements, sumInside2);
        res = Expression.expDiv(inside_sum1, inside_sum2);
      then
        res;
    // No inside components.
    case (_, {})
      equation
        outside_sum1 = sumMap(inOutsideElements, sumOutside1);
        outside_sum2 = sumMap(inOutsideElements, sumOutside2);
        res = Expression.expDiv(outside_sum1, outside_sum2);
      then
        res;
    // Both outside and inside components.
    else
      equation
        outside_sum1 = sumMap(inOutsideElements, sumOutside1);
        outside_sum2 = sumMap(inOutsideElements, sumOutside2);
        inside_sum1 = sumMap(inInsideElements, sumInside1);
        inside_sum2 = sumMap(inInsideElements, sumInside2);
        res = Expression.expDiv(Expression.expAdd(outside_sum1, inside_sum1),
                                Expression.expAdd(outside_sum2, inside_sum2));
      then
        res;
  end match;
end streamSumEquationExp;

protected function sumMap
  "Creates a sum expression by applying the given function on the list of
  elements and summing up the resulting expressions."
  input list<SetElement> inElements;
  input FuncType inFunc;
  output DAE.Exp outExp;
  
  replaceable type SetElement subtypeof Any;
  partial function FuncType
    input SetElement inElement;
    output DAE.Exp outExp;
  end FuncType;
algorithm
  outExp := match(inElements, inFunc)
    local
      SetElement elem;
      list<SetElement> rest_elem;
      DAE.Exp e1, e2;

    case ({elem}, _)
      equation
        e1 = inFunc(elem);
      then
        e1;

    case (elem :: rest_elem, _)
      equation
        e1 = inFunc(elem);
        e2 = sumMap(rest_elem, inFunc);
      then
        Expression.expAdd(e1, e2);
  end match;
end sumMap;

protected function streamFlowExp
  "Returns the stream and flow component in a stream set element as expressions."
  input Connect.StreamSetElement inElement;
  output DAE.Exp outStreamExp;
  output DAE.Exp outFlowExp;

  DAE.ComponentRef stream_cr, flow_cr;
algorithm
  (stream_cr, flow_cr, _, _) := inElement;
  outStreamExp := Expression.crefExp(stream_cr);
  outFlowExp := Expression.crefExp(flow_cr);
end streamFlowExp;

protected function flowExp
  "Returns the flow component in a stream set element as an expression."
  input Connect.StreamSetElement inElement;
  output DAE.Exp outFlowExp;

  DAE.ComponentRef flow_cr;
algorithm
  (_, flow_cr, _, _) := inElement;
  outFlowExp := Expression.crefExp(flow_cr);
end flowExp;

protected function sumOutside1
  "Helper function to streamSumEquationExp. Returns the expression 
    max(flow_exp, eps) * inStream(stream_exp)
  given a stream set element."
  input Connect.StreamSetElement inElement;
  output DAE.Exp outExp;

  DAE.Exp stream_exp, flow_exp;
algorithm
  (stream_exp, flow_exp) := streamFlowExp(inElement);
  outExp := Expression.expMul(makePositiveMaxCall(flow_exp),
                              makeInStreamCall(stream_exp));
end sumOutside1;

protected function sumInside1
  "Helper function to streamSumEquationExp. Returns the expression 
    max(-flow_exp, eps) * stream_exp
  given a stream set element."
  input Connect.StreamSetElement inElement;
  output DAE.Exp outExp;

  DAE.Exp stream_exp, flow_exp;
algorithm
  (stream_exp, flow_exp) := streamFlowExp(inElement);
  flow_exp := DAE.UNARY(DAE.UMINUS(DAE.ET_REAL()), flow_exp);
  outExp := Expression.expMul(makePositiveMaxCall(flow_exp), stream_exp);
end sumInside1;

protected function sumOutside2
  "Helper function to streamSumEquationExp. Returns the expression 
    max(flow_exp, eps)
  given a stream set element."
  input Connect.StreamSetElement inElement;
  output DAE.Exp outExp;

  DAE.Exp flow_exp;
algorithm
  flow_exp := flowExp(inElement);
  outExp := makePositiveMaxCall(flow_exp);
end sumOutside2;

protected function sumInside2
  "Helper function to streamSumEquationExp. Returns the expression 
    max(-flow_exp, eps)
  given a stream set element."
  input Connect.StreamSetElement inElement;
  output DAE.Exp outExp;

  DAE.Exp flow_exp;
algorithm
  flow_exp := flowExp(inElement);
  flow_exp := DAE.UNARY(DAE.UMINUS(DAE.ET_REAL()), flow_exp);
  outExp := makePositiveMaxCall(flow_exp);
end sumInside2;

protected function faceEqual "function: sameFace
Test for face equality."
  input Connect.Face inFace1;
  input Connect.Face inFace2;
  output Boolean sameFaces;
algorithm
  sameFaces := matchcontinue (inFace1,inFace2)
    local DAE.ComponentRef c;
    case (Connect.INSIDE(),Connect.INSIDE()) then true;
    case (Connect.OUTSIDE(),Connect.OUTSIDE()) then true;
    case (_,_) then false;
  end matchcontinue;
end faceEqual;

protected function makeInStreamCall
  "Creates an inStream call expression."
  input DAE.Exp inStreamExp;
  output DAE.Exp outInStreamCall;
algorithm
  outInStreamCall := DAE.CALL(Absyn.IDENT("inStream"), {inStreamExp}, false,
    false, DAE.ET_OTHER(), DAE.NO_INLINE());
end makeInStreamCall;

protected function makePositiveMaxCall
  "Generates a max(flow_exp, eps) call."
  input DAE.Exp inFlowExp;
  output DAE.Exp outPositiveMaxCall;
algorithm
  outPositiveMaxCall := DAE.CALL(Absyn.IDENT("max"), 
    {inFlowExp, DAE.RCONST(1e-15)}, false, true, DAE.ET_REAL(), DAE.NO_INLINE());
end makePositiveMaxCall;

public function evaluateInStream
  "This function evaluates the inStream operator for a component reference,
  given the connection sets."
  input DAE.ComponentRef inStreamCref;
  input Connect.Sets inSets;
  output DAE.Exp outExp;
algorithm
  outExp := matchcontinue(inStreamCref, inSets)
    local
      list<Connect.StreamSetElement> sl;
      DAE.Exp in_stream_exp;
    case (_, _)
      equation
        // Look up the connection set for the component (as inside).
        Connect.STREAM(sl) = findStreamSet(inSets, inStreamCref,
          ComponentReference.DUMMY, Connect.INSIDE(), DAE.emptyElementSource);
        in_stream_exp = generateInStreamExp(inStreamCref, sl, inSets);
      then
        in_stream_exp;
    case (_, _)
      equation
        true = RTOpts.debugFlag("failtrace");
        Debug.traceln("- ConnectUtil.evaluateInStream failed for " +&
          ComponentReference.crefStr(inStreamCref) +& "\n");
      then
        fail();
  end matchcontinue;
end evaluateInStream;

protected function generateInStreamExp
  "Helper function to evaluateInStream. Generates an expression for inStream
  given a connection set."
  input DAE.ComponentRef inStreamCref;
  input list<Connect.StreamSetElement> inStreams;
  input Connect.Sets inSets;
  output DAE.Exp outExp;
algorithm
  outExp := match(inStreamCref, inStreams, inSets)
    local
      DAE.ComponentRef c;
      Connect.Face f1, f2;
      DAE.Exp e;
      DAE.ElementSource src;
      Absyn.Info info;
      list<Connect.StreamSetElement> el, inside, outside;

    // Unconnected stream connector:
    // inStream(c) = c;
    case (_, {(c, _, Connect.INSIDE(), _)}, _) then Expression.crefExp(c);

    // Two inside connected stream connectors:
    // inStream(c1) = c2;
    // inStream(c2) = c1;
    case (_, {(_, _, Connect.INSIDE(), _), (_, _, Connect.INSIDE(), _)}, _)
      equation
        {(c, _, _, _)} = removeStreamSetElement(inStreamCref, inStreams);
        e = Expression.crefExp(c);
      then
        e;

    // One inside, one outside connected stream connector:
    // inStream(c1) = inStream(c2);
    case (_, {(_, _, f1, _), (_, _, f2, _)}, _)
      equation
        false = faceEqual(f1, f2);
        {(c, _, _, _)} = removeStreamSetElement(inStreamCref, inStreams);
        e = evaluateInStream(c, inSets);
      then
        e;

    // The general case:
    else
      equation
        (outside, inside) = Util.listSplitOnTrue(inStreams, isOutsideStream);
        inside = removeStreamSetElement(inStreamCref, inside);
        e = streamSumEquationExp(outside, inside);
      then
        e;
  end match;
end generateInStreamExp;

public function evaluateActualStream
  "This function evaluates the actualStream operator for a component reference,
  given the connection sets."
  input DAE.ComponentRef inStreamCref;
  input Connect.Sets inSets;
  output DAE.Exp outExp;
algorithm
  outExp := match(inStreamCref, inSets)
    local
      DAE.ComponentRef flow_cr;
      DAE.Exp e, flow_exp, stream_exp, instream_exp;
      DAE.ExpType ety;
    case (_, _)
      equation
        flow_cr = getStreamFlowAssociation(inStreamCref, inSets);
        ety = ComponentReference.crefType(inStreamCref);
        flow_exp = Expression.crefExp(flow_cr);
        stream_exp = Expression.crefExp(inStreamCref);
        instream_exp = evaluateInStream(inStreamCref, inSets);
        // actualStream(stream_var) = if flow_var > 0 then inStream(stream_var)
        //                                            else stream_var;
        e = DAE.IFEXP(DAE.RELATION(flow_exp, DAE.GREATER(ety), DAE.RCONST(0.0)),
            instream_exp, stream_exp);
      then
        e;  
  end match;
end evaluateActualStream;
        
//- Lookup
//  These functions are used to find and create connection sets.

protected function findEquSet "function: findEquSet
  This function finds a non-flow connection set that contains the
  component named by the second argument. If no such set is found,
  a new set is created."
  input Connect.Sets inSets;
  input DAE.ComponentRef inComponentRef;
  input DAE.ElementSource source "the element source";
  output Connect.Set outSet;
algorithm
  outSet := matchcontinue (inSets,inComponentRef,source)
    local
      Connect.Set s;
      DAE.ComponentRef c;
      list<Connect.Set> ss;
      list<Connect.EquSetElement> csEqu;      

    case (Connect.SETS(setLst = {}),c,source)
      equation
        s = newEquSet(c, source);
      then
        s;
    
    case (Connect.SETS(setLst = ((s as Connect.EQU(expComponentRefLst = csEqu)) :: _)),c,source)
      equation
        findInSetEqu(csEqu, c);
      then
        s;
    
    case (Connect.SETS(setLst = (_ :: ss)),c,source)
      equation
        s = findEquSet(setConnectSets(inSets, ss), c, source);
      then
        s;
  end matchcontinue;
end findEquSet;

protected function findFlowSet "function: findFlowSet
  This function finds a flow connection set that contains the
  component named by the second argument.  If no such set is found,
  a new set is created."
  input Connect.Sets inSets;
  input DAE.ComponentRef inComponentRef;
  input Connect.Face inFace;
  input DAE.ElementSource source "the element source";
  output Connect.Set outSet;
algorithm
  outSet := matchcontinue (inSets,inComponentRef,inFace,source)
    local
      Connect.Set s;
      DAE.ComponentRef c;
      Connect.Face d;
      list<Connect.Set> ss;
      list<Connect.FlowSetElement> cs;      

    case (Connect.SETS(setLst = {}),c,d,source)
      equation
        s = newFlowSet(c, d, source);
      then
        s;
    
    case (Connect.SETS(setLst = ((s as Connect.FLOW(tplExpComponentRefFaceLst = cs)) :: _)),c,d,source) 
      equation
        findInSetFlow(cs, c, d);
      then
        s;
    
    case (Connect.SETS(setLst = (_ :: ss)),c,d,source)
      equation
        s = findFlowSet(setConnectSets(inSets, ss), c, d, source);
      then
        s;
  end matchcontinue;
end findFlowSet;

protected function findInSetEqu "function: findInSetEqu
  This is a version of findInSet which is specialized on non-flow connection sets"
  input list<Connect.EquSetElement> inExpComponentRefLst;
  input DAE.ComponentRef inComponentRef;
algorithm
  _ := matchcontinue (inExpComponentRefLst,inComponentRef)
    local 
      DAE.ComponentRef c1,c2;
      list<Connect.EquSetElement> cs;
    case ((c1,_) :: _,c2) equation Static.eqCref(c1, c2); then ();
    case (_ :: cs,c2) equation findInSetEqu(cs, c2); then ();
  end matchcontinue;
end findInSetEqu;

protected function flowSetElementEqual
  input DAE.ComponentRef inComponentRef;
  input Connect.Face inFace;
  input Connect.FlowSetElement inElem;
  output Boolean isEqual;
algorithm
  isEqual := matchcontinue(inComponentRef, inFace, inElem)
    local
      DAE.ComponentRef cr;
      Connect.Face face;
    case (_, _, (cr, face, _))
      equation
        Static.eqCref(cr, inComponentRef);
        true = faceEqual(face, inFace);
      then
        true;
    case (_, _, _) then false;
  end matchcontinue;
end flowSetElementEqual;

protected function findInSetFlow "function: findInSetFlow
  This is a version of findInSet which is specialized on flow connection sets"
  input list<Connect.FlowSetElement> inTplExpComponentRefFaceLst;
  input DAE.ComponentRef inComponentRef;
  input Connect.Face inFace;
algorithm
  _ := matchcontinue (inTplExpComponentRefFaceLst, inComponentRef, inFace)
    local 
      Connect.FlowSetElement fe;
      list<Connect.FlowSetElement> cs;
    case (fe :: _, _, _) 
      equation 
        true = flowSetElementEqual(inComponentRef, inFace, fe);
      then ();
    case (_ :: cs, _, _) 
      equation 
        findInSetFlow(cs, inComponentRef, inFace); 
      then ();
  end matchcontinue;
end findInSetFlow;

protected function newEquSet "function: newEquSet
  This function creates a new non-flow connection
  set containing only the given component."
  input DAE.ComponentRef inComponentRef;
  input DAE.ElementSource source "the origin of the element";
  output Connect.Set outSet;
algorithm
  outSet := Connect.EQU({(inComponentRef, source)});
end newEquSet;

protected function newFlowSet "function: newFlowSet
  This function creates a new-flow connection set containing only
  the given component."
  input DAE.ComponentRef inComponentRef;
  input Connect.Face inFace;
  input DAE.ElementSource source "the origin of the element";
  output Connect.Set outSet;
algorithm
  outSet := Connect.FLOW({(inComponentRef, inFace, source)});
end newFlowSet;

protected function findStreamSet "function: findStreamSet
  This function finds a stream connection set that contains the component named
  by the second argument.  If no such set is found, a new set is created."
  input Connect.Sets inSets;
  input DAE.ComponentRef inStreamCref;
  input DAE.ComponentRef inFlowCref;
  input Connect.Face inFace;
  input DAE.ElementSource source "the element source";
  output Connect.Set outSet;
algorithm
  outSet := matchcontinue (inSets,inStreamCref,inFlowCref,inFace,source)
    local
      Connect.Set s;
      list<Connect.Set> sl;
      list<Connect.StreamSetElement> cs;      

    case (Connect.SETS(setLst = {}), _, _, _, _)
      equation
        s = newStreamSet(inStreamCref, inFlowCref, inFace, source);
      then
        s;
    
    case (Connect.SETS(setLst = (s as Connect.STREAM(tplExpComponentRefFaceLst = cs)) :: _), 
        _, _, _, _)
      equation
        findInSetStream(cs, inStreamCref, inFace);
      then
        s;
    
    case (Connect.SETS(setLst = (_ :: sl)), _, _, _, _)
      equation
        inSets = setConnectSets(inSets, sl);
        s = findStreamSet(inSets, inStreamCref, inFlowCref, inFace, source);
      then
        s;
  end matchcontinue;
end findStreamSet;

protected function findInSetStream
  "This is a version of findInSet which is specialized on stream connection
  sets."
  input list<Connect.StreamSetElement> inSets;
  input DAE.ComponentRef inComponentRef;
  input Connect.Face inFace;
algorithm
  _ := matchcontinue(inSets, inComponentRef, inFace)
    local
      DAE.ComponentRef c1, c2;
      Connect.Face f1, f2;
      list<Connect.StreamSetElement> cs;
    case ((c1, _, f1, _) :: _, c2, f2)
      equation
        Static.eqCref(c1, c2);
        true = faceEqual(f1, f2);
      then ();
    case (_ :: cs, c2, f2)
      equation
        findInSetStream(cs, c2, f2);
      then ();
  end matchcontinue;
end findInSetStream;

protected function newStreamSet "function: newStreamSet
  This function creates a new-stream connection set containing only
  the given component."
  input DAE.ComponentRef inStreamCref;
  input DAE.ComponentRef inFlowCref;
  input Connect.Face inFace;
  input DAE.ElementSource source "the origin of the element";
  output Connect.Set outSet;
algorithm
  outSet := Connect.STREAM({(inStreamCref, inFlowCref, inFace, source)});
end newStreamSet;

protected function setsEqual
  input Connect.Set inSet1;
  input Connect.Set inSet2;
  output Boolean equalSets;
algorithm
  equalSets := matchcontinue(inSet1,inSet2)
    local
      DAE.ComponentRef cr1,cr2;
      list<Connect.EquSetElement> equRest1,equRest2;
      list<Connect.FlowSetElement> flowRest1,flowRest2;
      list<Connect.StreamSetElement> streamRest1,streamRest2;
      Connect.Face face1,face2;

    // pointer equality testing first.
    case (inSet1, inSet2)
      equation
        true = referenceEq(inSet1, inSet2);         
      then true;

    // deal with empty case
    case (Connect.EQU({}), Connect.EQU({})) then true;
    case (Connect.FLOW({}), Connect.FLOW({})) then true;
    case (Connect.STREAM({}), Connect.STREAM({})) then true;      

    // deal with non empty Connect.EQU
    case (Connect.EQU((cr1,_)::equRest1), 
          Connect.EQU((cr2,_)::equRest2))
      equation
        true = ComponentReference.crefEqualNoStringCompare(cr1, cr2);
        true = setsEqual(Connect.EQU(equRest1),Connect.EQU(equRest2));
      then
        true;

    // deal with non empty Connect.FLOW
    case (Connect.FLOW((cr1,face1,_)::flowRest1), 
          Connect.FLOW((cr2,face2,_)::flowRest2))
      equation
        true = faceEqual(face1, face2);
        true = ComponentReference.crefEqualNoStringCompare(cr1, cr2);
        true = setsEqual(Connect.FLOW(flowRest1),Connect.FLOW(flowRest2));
      then
        true;

    // deal with non empty Connect.STREAM
    case (Connect.STREAM((cr1,_,face1,_)::streamRest1), 
          Connect.STREAM((cr2,_,face2,_)::streamRest2))
      equation
        true = faceEqual(face1, face2);
        true = ComponentReference.crefEqualNoStringCompare(cr1, cr2);
        true = setsEqual(Connect.STREAM(streamRest1),Connect.STREAM(streamRest2));
      then
        true;        
    case (_, _) then false;
  end matchcontinue;
end setsEqual;

//- Merging

protected function merge "function: merge
  The result of merging two connection sets
  is the intersection of the two sets."
  input Connect.Sets inSets;
  input Connect.Set inSet1;
  input Connect.Set inSet2;
  output Connect.Sets outSets;
algorithm
  outSets := matchcontinue (inSets,inSet1,inSet2)
    local
      Connect.Sets sets;
      // potential
      list<Connect.EquSetElement> pcs,pcs1,pcs2;
      // flow
      list<Connect.FlowSetElement> fcs,fcs1,fcs2;
      // stream
      list<Connect.StreamSetElement> scs,scs1,scs2;
      Connect.Set s1,s2;
    
    // sets are equal, do nothing
    case (inSets,s1,s2)
      equation
        true = setsEqual(s1,s2);
      then
        inSets;

    // potential
    case (sets,
          (s1 as Connect.EQU(expComponentRefLst = pcs1)),
          (s2 as Connect.EQU(expComponentRefLst = pcs2)))
      equation
        pcs = Util.listMergeSorted(pcs1, pcs2, equSetElementLess);
        sets = removeSet2(sets, s1, s2);
        sets = addConnectSet(sets, Connect.EQU(pcs));
      then
        sets;
    
    // flow
    case (sets,
          (s1 as Connect.FLOW(tplExpComponentRefFaceLst = fcs1)),
          (s2 as Connect.FLOW(tplExpComponentRefFaceLst = fcs2)))
      equation
        fcs = listAppend(fcs1, fcs2);
        sets = removeSet2(sets, s1, s2);
        sets = addConnectSet(sets, Connect.FLOW(fcs));
      then
        sets;
    
    // stream
    case (sets,
          (s1 as Connect.STREAM(tplExpComponentRefFaceLst = scs1)),
          (s2 as Connect.STREAM(tplExpComponentRefFaceLst = scs2)))      
      equation
        scs = listAppend(scs1, scs2);
        sets = removeSet2(sets, s1, s2);
        sets = addConnectSet(sets, Connect.STREAM(scs));
      then
        sets;
  end matchcontinue;
end merge;

protected function equSetElementLess
  "Compares two potiential set elements, and returns true if the first element
  is less than the second element. This is used in merge to keep potential sets
  sorted when merging them."
  input Connect.EquSetElement inElem1;
  input Connect.EquSetElement inElem2;
  output Boolean res;
algorithm
  res := matchcontinue(inElem1, inElem2)
    local
      DAE.ComponentRef cr1, cr2;
    
    case ((cr1, _), (cr2, _)) then ComponentReference.crefSortFunc(cr2, cr1);
  end matchcontinue;
end equSetElementLess;

protected function removeSet2 "function: removeSet2
  This function removes the two sets given in the second and third
  argument from the collection of sets given in the first argument."
  input Connect.Sets inSets;
  input Connect.Set inSet1;
  input Connect.Set inSet2;
  output Connect.Sets outSets;
algorithm
  outSets := matchcontinue (inSets,inSet1,inSet2)
    local
      Connect.Set s,s1,s2;
      list<Connect.Set> ss;
      Connect.Sets sets;

    case (Connect.SETS(setLst = {}),_,_)
      then inSets;

    case (Connect.SETS(setLst = (s :: ss)),s1,s2)
      equation
        true = setsEqual(s, s1);
        sets = removeSet(setConnectSets(inSets, ss), s2);
      then
        sets;

    case (Connect.SETS(setLst = (s :: ss)),s1,s2)
      equation
        true = setsEqual(s, s2);
        sets = removeSet(setConnectSets(inSets, ss), s1);
      then
        sets;

    case (Connect.SETS(setLst = (s :: ss)),s1,s2)
      equation
        sets = removeSet2(setConnectSets(inSets, ss), s1, s2);
        sets = addConnectSet(sets, s);
      then
        sets;
  end matchcontinue;
end removeSet2;

protected function removeSet "function: removeSet
  This function removes one set from a list of sets."
  input Connect.Sets inSets;
  input Connect.Set inSet;
  output Connect.Sets outSets;

  list<Connect.Set> sl;
algorithm
  Connect.SETS(setLst = sl) := inSets;
  sl := Util.listRemoveFirstOnTrue(inSet, setsEqual, sl);
  outSets := setConnectSets(inSets, sl);
end removeSet;

protected function removeUnconnectedFlowVariable
  "This function searches for a flow variable that is unconnected, i.e. that is
  alone in a connection set, and removes the set from the connection sets."
  input DAE.ComponentRef inComponentRef;
  input Connect.Face inFace;
  input list<Connect.Set> inSets;
  output list<Connect.Set> outSets;
algorithm
  outSets := matchcontinue(inComponentRef, inFace, inSets)
    local
      Connect.FlowSetElement fe;
      list<Connect.Set> sets;
      Connect.Set s;
    
    case (_, _, {}) then {};
    
    case (_, _, Connect.FLOW(tplExpComponentRefFaceLst = {fe}) :: sets)
      equation
        true = flowSetElementEqual(inComponentRef, inFace, fe);
      then
        sets;
    
    case (_, _, s :: sets)
      equation
        sets = removeUnconnectedFlowVariable(inComponentRef, inFace, sets);
      then
        s :: sets;
  end matchcontinue;
end removeUnconnectedFlowVariable;

protected function removeStreamSetElement
  "This function removes the given cref from a connection set."
  input DAE.ComponentRef inCref;
  input list<Connect.StreamSetElement> inElements;
  output list<Connect.StreamSetElement> outElements;
algorithm
  outElements := Util.listRemoveFirstOnTrue(inCref, compareCrefStreamSet,
    inElements);
end removeStreamSetElement;
        
protected function compareCrefStreamSet
  "Helper function to removeStreamSetElement. Checks if the cref in a stream set
  element matches the given cref."
  input DAE.ComponentRef inCref;
  input Connect.StreamSetElement inElement;
  output Boolean outRes;
algorithm
  outRes := matchcontinue(inCref, inElement)
    local
      DAE.ComponentRef cr;
    case (_, (cr, _, _, _))
      equation
        true = ComponentReference.crefEqualNoStringCompare(inCref, cr);
      then
        true;
    else then false;
  end matchcontinue;
end compareCrefStreamSet;

/*
  - Printing

  These are a few functions used for printing a description of the
  connection sets.  The implementation is excluded from the report
  for brevity.
*/

public function printSets "function: printSets
  Prints a description of a number of connection sets to the
  standard output."
  input Connect.Sets inSets;
algorithm
  _ := matchcontinue (inSets)
    local
      Connect.Set x;
      list<Connect.Set> xs;
      list<DAE.ComponentRef> crs,dc;
      list<Connect.OuterConnect> outerConn;
    
    case Connect.SETS(setLst = {}) then ();
    
    case Connect.SETS(setLst = (x :: xs))
      equation
        printSet(x);
        printSets(setConnectSets(inSets, xs));
      then
        ();
  end matchcontinue;
end printSets;

protected function printSet ""
  input Connect.Set inSet;
algorithm
  Print.printBuf(printSetStr(inSet));
end printSet;

protected function printFlowRef
  input Connect.FlowSetElement inTplExpComponentRefFace;
algorithm
  Print.printBuf(printFlowRefStr(inTplExpComponentRefFace));
end printFlowRef;

protected function printStreamRef
  input Connect.StreamSetElement inTplExpComponentRefFace;
algorithm
  Print.printBuf(printStreamRefStr(inTplExpComponentRefFace));
end printStreamRef;

public function printSetsStr "function: printSetsStr
  Prints a description of a number of connection sets to a string"
  input Connect.Sets inSets;
  output String outString;
algorithm
  outString := matchcontinue (inSets)
    local
      list<String> s1;
      String s1_1,s2,res,s3,s4;
      list<Connect.Set> sets;
      list<DAE.ComponentRef> crs;
      list<DAE.ComponentRef> dc;
      list<Connect.OuterConnect> outerConn;
    case Connect.SETS(setLst = {},connection = {},deletedComponents = {},outerConnects = {})
      equation
        res = "Connect.SETS( EMPTY )\n";
      then
        res;
    case Connect.SETS(setLst = sets,connection = crs,deletedComponents=dc,outerConnects=outerConn)
      equation
        s1 = Util.listMap(sets, printSetStr);
        s1_1 = Util.stringDelimitList(s1, ", ");
        s2 = printSetCrsStr(crs);
        s3 = Util.stringDelimitList(Util.listMap(dc,ComponentReference.printComponentRefStr), ",");
        s4 = printOuterConnectsStr(outerConn);
        res = stringAppendList({"Connect.SETS(\n\t",
          s1_1,", \n\t",
          s2,", \n\tdeleted comps: ",s3,", \n\touter connections:",s4,")\n"});
      then
        res;
  end matchcontinue;
end printSetsStr;

protected function printOuterConnectsStr "prints the outer connections to a string, see also printSetsStr"
  input list<Connect.OuterConnect> outerConn;
  output String str;
algorithm
  str := matchcontinue(outerConn)
    local
      String s0, s1,s2,s3; DAE.ComponentRef cr1,cr2;
      Absyn.InnerOuter io1,io2;
      Prefix.Prefix prefix;

    case({}) then "";

    case(Connect.OUTERCONNECT(prefix,cr1,io1,_,cr2,io2,_,_)::outerConn) equation
      s0 = PrefixUtil.printPrefixStr(prefix);
      s1 = printOuterConnectsStr(outerConn);
      s2 = ComponentReference.printComponentRefStr(cr1);
      s3 = ComponentReference.printComponentRefStr(cr2);
      str = "(" +& s0 +& ", " +& s2 +& "("+& Dump.unparseInnerouterStr(io1) +&"), " +& s3 +&"("+& Dump.unparseInnerouterStr(io2) +& ") ) ," +& s1;
    then str;
  end matchcontinue;
end printOuterConnectsStr;

protected function printSetStr " a function to print the connection set "
  input Connect.Set inSet;
  output String outString;
algorithm
  outString := matchcontinue (inSet)
    local
      list<String> strs;
      String s1,res;
      list<Connect.EquSetElement> csEqu;
      list<Connect.FlowSetElement> csFlow;
      list<Connect.StreamSetElement> csStream;
    
    case Connect.EQU(expComponentRefLst = csEqu)
      equation
        strs = Util.listMap(Util.listMap(csEqu, Util.tuple21), ComponentReference.printComponentRefStr);
        s1 = Util.stringDelimitList(strs, ", ");
        res = stringAppendList({"\n\tnon-flow set: {",s1,"}"});
      then
        res;
    case Connect.FLOW(tplExpComponentRefFaceLst = csFlow)
      equation
        strs = Util.listMap(csFlow, printFlowRefStr);
        s1 = Util.stringDelimitList(strs, ", ");
        res = stringAppendList({"\n\tflow set: {",s1,"}"});
      then
        res;
    case Connect.STREAM(tplExpComponentRefFaceLst = csStream)
      equation
        strs = Util.listMap(csStream, printStreamRefStr);
        s1 = Util.stringDelimitList(strs, ", ");
        res = stringAppendList({"\n\tstream set: {",s1,"}"});
      then
        res;        
  end matchcontinue;
end printSetStr;

public function printFlowRefStr
  input Connect.FlowSetElement inTplExpComponentRefFace;
  output String outString;
algorithm
  outString := matchcontinue (inTplExpComponentRefFace)
    local
      String s,res;
      DAE.ComponentRef c;
    
    case ((c,Connect.INSIDE(),_))
      equation
        s = ComponentReference.printComponentRefStr(c);
        res = stringAppend(s, " INSIDE");
      then
        res;
    
    case ((c,Connect.OUTSIDE(),_))
      equation
        s = ComponentReference.printComponentRefStr(c);
        res = stringAppend(s, " OUTSIDE");
      then
        res;
  end matchcontinue;
end printFlowRefStr;

public function printStreamRefStr
  input Connect.StreamSetElement inTplExpComponentRefFace;
  output String outString;
algorithm
  outString := matchcontinue (inTplExpComponentRefFace)
    local
      String s,res;
      DAE.ComponentRef c;
      
    case ((c,_,Connect.INSIDE(),_))
      equation
        s = ComponentReference.printComponentRefStr(c);
        res = stringAppend(s, " INSIDE");
      then
        res;
    
    case ((c,_,Connect.OUTSIDE(),_))
      equation
        s = ComponentReference.printComponentRefStr(c);
        res = stringAppend(s, " OUTSIDE");
      then
        res;
  end matchcontinue;
end printStreamRefStr;

protected function printSetCrsStr
  input list<DAE.ComponentRef> crs;
  output String res;
  list<String> c_strs;
  String s;
algorithm
  c_strs := Util.listMap(crs, ComponentReference.printComponentRefStr);
  s := Util.stringDelimitList(c_strs, ", ");
  res := stringAppendList({"connect crs: {",s,"}"});
end printSetCrsStr;

public function componentFace
"function: componentFace
  This function determines whether a component
  reference refers to an inner or outer connector:
  Rules:
    qualified cref and connector     => OUTSIDE
    non-qualifed cref                => OUTSIDE
    qualified cref and non-connector => INSIDE

  Modelica Specification 4.0 
  Section: 9.1.2 Inside and Outside Connectors
  In an element instance M, each connector element of M is called an outside connector with respect to M. 
  All other connector elements that are hierarchically inside M, but not in one of the outside connectors 
  of M, is called an inside connector with respect to M. This is done **BEFORE** resolving outer elements 
  to corresponding inner ones."
  input Env.Env env;
  input InnerOuter.InstHierarchy inIH;
  input DAE.ComponentRef inComponentRef;
  output Connect.Face outFace;
algorithm
  outFace := matchcontinue (env,inIH,inComponentRef)
    local
      DAE.ComponentRef cr,cref_;
      DAE.Ident id;
      InnerOuter.InstHierarchy ih;

    // is a non-qualified cref => OUTSIDE
    case (env,ih,DAE.CREF_IDENT(ident = _)) 
      then Connect.OUTSIDE();

    // is a qualified cref and is a connector => OUTSIDE 
    case (env,ih,DAE.CREF_QUAL(ident = id,componentRef = cr)) 
      equation
       (_,_,(DAE.T_COMPLEX(complexClassType=ClassInf.CONNECTOR(_,_)),_),_,_,_,_,_,_) 
         = Lookup.lookupVar(Env.emptyCache(),env,ComponentReference.makeCrefIdent(id,DAE.ET_OTHER(),{}));
      then Connect.OUTSIDE();

    // is a qualified cref and is NOT a connector => INSIDE
    case (env,ih,DAE.CREF_QUAL(componentRef =_)) 
      then Connect.INSIDE();
  end matchcontinue;
end componentFace;

public function componentFaceType
"function: componentFaceType
  Author: BZ, 2008-12
  Same functionalty as componentFace, with the difference that 
  this function checks ident-type rather then env->lookup ==> type.
  Rules:
    qualified cref and connector     => OUTSIDE
    non-qualifed cref                => OUTSIDE
    qualified cref and non-connector => INSIDE
  
  Modelica Specification 4.0 
  Section: 9.1.2 Inside and Outside Connectors
  In an element instance M, each connector element of M is called an outside connector with respect to M. 
  All other connector elements that are hierarchically inside M, but not in one of the outside connectors 
  of M, is called an inside connector with respect to M. This is done **BEFORE** resolving outer elements 
  to corresponding inner ones."
  input DAE.ComponentRef inComponentRef;
  output Connect.Face outFace;
algorithm
  outFace := matchcontinue (inComponentRef)
    // is a non-qualified cref => OUTSIDE
    case (DAE.CREF_IDENT(ident = _)) then Connect.OUTSIDE();
    // is a qualified cref and is a connector => OUTSIDE
    case (DAE.CREF_QUAL(identType = DAE.ET_COMPLEX(complexClassType=ClassInf.CONNECTOR(_,_)))) then Connect.OUTSIDE();
    // is a qualified cref and is NOT a connector => INSIDE
    case (DAE.CREF_QUAL(componentRef =_)) then Connect.INSIDE();
  end matchcontinue;
end componentFaceType;

public function updateConnectionSetTypes "function: updateConnectionSetTypes
When instantiating connection_sets we have no type information on them.
So this is what till function will do, update type information on csets."
  input Connect.Sets csets;
  input DAE.ComponentRef typedRef;
  output Connect.Sets updatedEnv;
algorithm 
  updatedEnv := matchcontinue(csets,typedRef)
    local
      list<DAE.ComponentRef> c;
    
    case(Connect.SETS(connection = c), typedRef)
      equation
        //TODO: update types for rest of set
        c = updateConnectionSetTypesCrefs(c, typedRef);
      then
        setConnectionCrefs(csets, c);
    
    case(_,_)
      equation
        Debug.fprint("failtrace", "- updateConnectionSetTypes failed");
      then
        fail();
  end matchcontinue;
end updateConnectionSetTypes;

protected function updateConnectionSetTypesCrefs "function: updateConnectionSetTypes2
helper function for updateConnectionSetTypes"
  input list<DAE.ComponentRef> list1;
  input DAE.ComponentRef list2;
  output list<DAE.ComponentRef> list3;
algorithm 
  list3 := matchcontinue(list1,list2)
    local
      list<DAE.ComponentRef> cr1s,cr2s;
      DAE.ComponentRef cr1,cr2;
    // empty case
    case({},_) then {};
    // found something, replace the cref in the list 
    case(cr1::cr1s, cr2)
      equation
        true = ComponentReference.crefEqual(cr1,cr2);
        cr2s = updateConnectionSetTypesCrefs(cr1s,cr2);
      then
        cr2::cr2s;
    // move along to some better part of the day
    case(cr1::cr1s,cr2)
      equation
        cr2s = updateConnectionSetTypesCrefs(cr1s,cr2);
      then
        cr1::cr2s;
  end matchcontinue;
end updateConnectionSetTypesCrefs;

public function checkConnectorBalance
  "Checks if a connector class is balanced or not, according to the rules in the
  Modelica 3.2 specification."
  input list<DAE.Var> inVars;
  input Absyn.Path path;
  input Absyn.Info info;
algorithm
  _ := matchcontinue(inVars, path, info)
    local
      Integer potentials, flows, streams;

    // Only do balance checking if the checkconnect debug flag is set.
    case (_, _, _)
      equation
        false = RTOpts.debugFlag("checkconnect");
      then
        ();

    else
      equation
        (potentials, flows, streams) = countConnectorVars(inVars);
        checkConnectorBalance2(potentials, flows, streams, path, info);
        //print(Absyn.pathString(path) +& " has:\n\t" +&
        //  intString(potentials) +& " potential variables\n\t" +&
        //  intString(flows) +& " flow variables\n\t" +&
        //  intString(streams) +& " stream variables\n\n");
      then
        ();
  end matchcontinue;
end checkConnectorBalance;

protected function checkConnectorBalance2
  input Integer inPotentialVars;
  input Integer inFlowVars;
  input Integer inStreamVars;
  input Absyn.Path path;
  input Absyn.Info info;
algorithm
  _ := matchcontinue(inPotentialVars, inFlowVars, inStreamVars, path, info)
    local
      String error_str, flow_str, potential_str, class_str; 

    // The connector is balanced.
    case (_, _, _, _, _)
      equation
        true = intEq(inPotentialVars, inFlowVars);
        true = Util.if_(intEq(inStreamVars, 0), true, intEq(inFlowVars, 1));
      then
        ();

    // Modelica 3.2 section 9.3.1:
    // For each non-partial connector class the number of flow variables shall
    // be equal to the number of variables that are neither parameter, constant,
    // input, output, stream nor flow.
    case (_, _, _, _, _)
      equation
        false = intEq(inPotentialVars, inFlowVars);
        flow_str = intString(inFlowVars);
        potential_str = intString(inPotentialVars);
        class_str = Absyn.pathString(path);
        error_str = stringAppendList({
          "The number of potential variables (",
          potential_str,
          ") is not equal to the number of flow variables (",
          flow_str, ")."});
        Error.addSourceMessage(Error.UNBALANCED_CONNECTOR,
          {class_str, error_str}, info);
      then 
        fail();

    // Modelica 3.2 section 15.1:
    // A stream connector must have exactly one scalar variable with the flow prefix.
    case (_, _, _, _, _)
      equation
        false = intEq(inStreamVars, 0);
        false = intEq(inFlowVars, 1);
        flow_str = intString(inFlowVars);
        class_str = Absyn.pathString(path);
        error_str = stringAppendList({
          "A stream connector must have exactly one flow variable, this connector has ", 
          flow_str, " flow variables."}); 
        Error.addSourceMessage(Error.UNBALANCED_CONNECTOR,
          {class_str, error_str}, info);
      then
        fail(); 
  end matchcontinue;
end checkConnectorBalance2;

protected function countConnectorVars
  "Given a list of connector variables, this function counts how many potential,
  flow and stream variables it contains."
  input list<DAE.Var> inVars;
  output Integer potentialVars;
  output Integer flowVars;
  output Integer streamVars;
algorithm
  (potentialVars, flowVars, streamVars) := matchcontinue(inVars)
    local
      DAE.Var v;
      list<DAE.Var> rest, vars;
      Integer n, p, f, s, p2, f2, s2;
      String name;
      DAE.Type ty, ty2;

    case ({}) then (0, 0, 0);

    // A connector inside a connector.
    case ((v as DAE.TYPES_VAR(name = name, type_ = ty)) :: rest)
      equation
        // Check that it's a connector.
        ty2 = Types.arrayElementType(ty);
        true = Types.isComplexConnector(ty2);
        // If we have an array of connectors, count how many they are.
        n = Util.listFold(Types.getDimensionSizes(ty), intMul, 1);
        // Count the number of different variables inside the connector, and
        // then multiply those numbers with the dimensions of the array.
        vars = Types.getConnectorVars(ty2);
        (p2, f2, s2) = countConnectorVars(vars);
        (p, f, s) = countConnectorVars(rest);
      then
        (p + n * p2, f + n * f2, s + n * s2);

    // A flow variable.
    case ((v as DAE.TYPES_VAR(attributes = DAE.ATTR(flowPrefix = true))) :: rest)
      equation
        n = sizeOfVariable(v);
        (p, f, s) = countConnectorVars(rest);
      then
        (p, f + n, s);

    // A stream variable.
    case ((v as DAE.TYPES_VAR(attributes = DAE.ATTR(streamPrefix = true))) :: rest)
      equation
        n = sizeOfVariable(v);
        (p, f, s) = countConnectorVars(rest);
      then
        (p, f, s + n);

    // A potential variable.
    case ((v as DAE.TYPES_VAR(attributes = DAE.ATTR(
        direction = Absyn.BIDIR(),
        parameter_ = SCode.VAR()))) :: rest)
      equation
        n = sizeOfVariable(v);
        (p, f, s) = countConnectorVars(rest);
      then
        (p + n, f, s);

    // Something else.
    case _ :: rest
      equation
        (p, f, s) = countConnectorVars(rest);
      then
        (p, f, s);
  end matchcontinue;
end countConnectorVars;

protected function sizeOfVariableList
  "Calls sizeOfVariable on a list of variables, and adds up the results."
  input list<DAE.Var> inVar;
  output Integer outSize;

  list<Integer> sizes;
algorithm
  sizes := Util.listMap(inVar, sizeOfVariable);
  outSize := Util.listFold(sizes, intAdd, 0);
end sizeOfVariableList;

protected function sizeOfVariable
  "Different types of variables have different size, for example arrays. This
  function checks the size of one variable."
  input DAE.Var inVar;
  output Integer outSize;
algorithm
  outSize := matchcontinue(inVar)
    local DAE.Type t;
    case DAE.TYPES_VAR(type_ = t) then sizeOfVariable2(t);
  end matchcontinue;
end sizeOfVariable; 

protected function sizeOfVariable2
  "Helper function to sizeOfVariable."
  input DAE.Type inType;
  output Integer outSize;
algorithm
  outSize := matchcontinue(inType)
    local
      Integer n;
      DAE.Type t;
      list<DAE.Var> v;

    // Scalar values consist of one element.
    case ((DAE.T_INTEGER(_), _)) then 1;
    case ((DAE.T_REAL(_), _)) then 1;
    case ((DAE.T_STRING(_), _)) then 1;
    case ((DAE.T_BOOL(_), _)) then 1;
    case ((DAE.T_ENUMERATION(index = NONE()), _)) then 1;
    // The size of an array is its dimension multiplied with the size of its type.
    case ((DAE.T_ARRAY(arrayDim = DAE.DIM_INTEGER(integer = n), arrayType = t), _))
      then n * sizeOfVariable2(t);
    // The size of a complex type without an equalityConstraint (such as a
    // record), is the sum of the sizes of its components.
    case ((DAE.T_COMPLEX(complexVarLst = v, equalityConstraint = NONE()), _))
      then sizeOfVariableList(v);
    // The size of a complex type with an equalityConstraint function is
    // determined by the size of the return value of that function.
    case ((DAE.T_COMPLEX(equalityConstraint = SOME((_, n, _))), _)) then n;
    // Anything we forgot?
    case t
      equation
        Debug.fprintln("failtrace", "- Inst.sizeOfVariable failed on " +&
          Types.printTypeStr(t));
      then
        fail();
  end matchcontinue;
end sizeOfVariable2;

end ConnectUtil;

