/**
 * @license
 * Copyright 2015 The Incremental DOM Authors. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS-IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
!function(t,e){"object"==typeof exports&&"undefined"!=typeof module?e(exports):"function"==typeof define&&define.amd?define(["exports"],e):e(t.IncrementalDOM={})}(this,function(t){"use strict";function e(){}function n(t,e){this.attrs=a(),this.attrsArr=[],this.newAttrs=a(),this.staticsApplied=!1,this.key=e,this.keyMap=a(),this.keyMapValid=!0,this.focused=!1,this.nodeName=t,this.text=null}function r(){this.created=h.nodesCreated&&[],this.deleted=h.nodesDeleted&&[]}var i=Object.prototype.hasOwnProperty;e.prototype=Object.create(null);var o=function(t,e){return i.call(t,e)},a=function(){return new e},u="__incrementalDOMData",l=function(t,e,r){var i=new n(e,r);return t[u]=i,i},f=function(t){return c(t),t[u]},c=function(t){if(!t[u]){var e=t instanceof Element,n=e?t.localName:t.nodeName,r=e?t.getAttribute("key"):null,i=l(t,n,r);if(r&&(f(t.parentNode).keyMap[r]=t),e)for(var o=t.attributes,a=i.attrs,s=i.newAttrs,d=i.attrsArr,p=0;p<o.length;p+=1){var h=o[p],v=h.name,m=h.value;a[v]=m,s[v]=void 0,d.push(v),d.push(m)}for(var y=t.firstChild;y;y=y.nextSibling)c(y)}},s=function(t,e){return"svg"===t?"http://www.w3.org/2000/svg":"foreignObject"===f(e).nodeName?null:e.namespaceURI},d=function(t,e,n,r){var i=s(n,e),o=void 0;return o=i?t.createElementNS(i,n):t.createElement(n),l(o,n,r),o},p=function(t){var e=t.createTextNode("");return l(e,"#text",null),e},h={nodesCreated:null,nodesDeleted:null};r.prototype.markCreated=function(t){this.created&&this.created.push(t)},r.prototype.markDeleted=function(t){this.deleted&&this.deleted.push(t)},r.prototype.notifyChanges=function(){this.created&&this.created.length>0&&h.nodesCreated(this.created),this.deleted&&this.deleted.length>0&&h.nodesDeleted(this.deleted)};var v=function(t){return t instanceof Document||t instanceof DocumentFragment},m=function(t,e){for(var n=[],r=t;r!==e;)n.push(r),r=r.parentNode;return n},y=function(t){for(var e=t,n=e;e;)n=e,e=e.parentNode;return n},g=function(t){var e=y(t);return v(e)?e.activeElement:null},k=function(t,e){var n=g(t);return n&&t.contains(n)?m(n,e):[]},x=function(t,e,n){for(var r=e.nextSibling,i=n;i!==e;){var o=i.nextSibling;t.insertBefore(i,r),i=o}},w=null,b=null,N=null,C=null,A=function(t,e){for(var n=0;n<t.length;n+=1)f(t[n]).focused=e},D=function(t){var e=function(e,n,i){var o=w,a=C,u=b,l=N;w=new r,C=e.ownerDocument,N=e.parentNode;var f=k(e,N);A(f,!0);var c=t(e,n,i);return A(f,!1),w.notifyChanges(),w=o,C=a,b=u,N=l,c};return e},O=D(function(t,e,n){return b=t,V(),e(n),T(),t}),M=D(function(t,e,n){var r={nextSibling:t};return b=r,e(n),t!==b&&t.parentNode&&j(N,t,f(N).keyMap),r===b?null:b}),S=function(t,e,n){var r=f(t);return e===r.nodeName&&n==r.key},E=function(t,e){if(!b||!S(b,t,e)){var n=f(N),r=b&&f(b),i=n.keyMap,o=void 0;if(e){var a=i[e];a&&(S(a,t,e)?o=a:a===b?w.markDeleted(a):j(N,a,i))}o||(o="#text"===t?p(C):d(C,N,t,e),e&&(i[e]=o),w.markCreated(o)),f(o).focused?x(N,o,b):r&&r.key&&!r.focused?(N.replaceChild(o,b),n.keyMapValid=!1):N.insertBefore(o,b),b=o}},j=function(t,e,n){t.removeChild(e),w.markDeleted(e);var r=f(e).key;r&&delete n[r]},I=function(){var t=N,e=f(t),n=e.keyMap,r=e.keyMapValid,i=t.lastChild,o=void 0;if(i!==b||!r){for(;i!==b;)j(t,i,n),i=t.lastChild;if(!r){for(o in n)i=n[o],i.parentNode!==t&&(w.markDeleted(i),delete n[o]);e.keyMapValid=!0}}},V=function(){N=b,b=null},P=function(){return b?b.nextSibling:N.firstChild},_=function(){b=P()},T=function(){I(),b=N,N=N.parentNode},B=function(t,e){return _(),E(t,e),V(),N},F=function(){return T(),b},L=function(){return _(),E("#text",null),b},R=function(){return N},U=function(){return P()},X=function(){b=N.lastChild},q=_,z={"default":"__default"},G=function(t){return 0===t.lastIndexOf("xml:",0)?"http://www.w3.org/XML/1998/namespace":0===t.lastIndexOf("xlink:",0)?"http://www.w3.org/1999/xlink":void 0},H=function(t,e,n){if(null==n)t.removeAttribute(e);else{var r=G(e);r?t.setAttributeNS(r,e,n):t.setAttribute(e,n)}},J=function(t,e,n){t[e]=n},K=function(t,e,n){e.indexOf("-")>=0?t.setProperty(e,n):t[e]=n},Q=function(t,e,n){if("string"==typeof n)t.style.cssText=n;else{t.style.cssText="";var r=t.style,i=n;for(var a in i)o(i,a)&&K(r,a,i[a])}},W=function(t,e,n){var r=typeof n;"object"===r||"function"===r?J(t,e,n):H(t,e,n)},Y=function(t,e,n){var r=f(t),i=r.attrs;if(i[e]!==n){var o=Z[e]||Z[z["default"]];o(t,e,n),i[e]=n}},Z=a();Z[z["default"]]=W,Z.style=Q;var $=3,tt=[],et=function(t,e,n){var r=B(t,e),i=f(r);if(!i.staticsApplied){if(n)for(var o=0;o<n.length;o+=2){var a=n[o],u=n[o+1];Y(r,a,u)}i.staticsApplied=!0}for(var l=i.attrsArr,c=i.newAttrs,s=!l.length,d=$,p=0;d<arguments.length;d+=2,p+=2){var h=arguments[d];if(s)l[p]=h,c[h]=void 0;else if(l[p]!==h)break;var u=arguments[d+1];(s||l[p+1]!==u)&&(l[p+1]=u,Y(r,h,u))}if(d<arguments.length||p<l.length){for(;d<arguments.length;d+=1,p+=1)l[p]=arguments[d];for(p<l.length&&(l.length=p),d=0;d<l.length;d+=2){var a=l[d],u=l[d+1];c[a]=u}for(var v in c)Y(r,v,c[v]),c[v]=void 0}return r},nt=function(t,e,n){tt[0]=t,tt[1]=e,tt[2]=n},rt=function(t,e){tt.push(t),tt.push(e)},it=function(){var t=et.apply(null,tt);return tt.length=0,t},ot=function(){var t=F();return t},at=function(t){return et.apply(null,arguments),ot(t)},ut=function(t){var e=L(),n=f(e);if(n.text!==t){n.text=t;for(var r=t,i=1;i<arguments.length;i+=1){var o=arguments[i];r=o(r)}e.data=r}return e};t.patch=O,t.patchInner=O,t.patchOuter=M,t.currentElement=R,t.currentPointer=U,t.skip=X,t.skipNode=q,t.elementVoid=at,t.elementOpenStart=nt,t.elementOpenEnd=it,t.elementOpen=et,t.elementClose=ot,t.text=ut,t.attr=rt,t.symbols=z,t.attributes=Z,t.applyAttr=H,t.applyProp=J,t.notifications=h,t.importNode=c});

var jsonml2idom = (function () {
	"use strict";

	var elementOpenStart = IncrementalDOM.elementOpenStart
	var elementOpenEnd = IncrementalDOM.elementOpenEnd
	var elementClose = IncrementalDOM.elementClose
	var currentElement = IncrementalDOM.currentElement
	var skip = IncrementalDOM.skip
	var attr = IncrementalDOM.attr
	var text = IncrementalDOM.text

	function openTag(head, keyAttr) {
		var dotSplit = head.split('.')
		var hashSplit = dotSplit[0].split('#')

		var tagName = hashSplit[0] || 'div'
		var id = hashSplit[1]
		var className = dotSplit.slice(1).join(' ')

		elementOpenStart(tagName, keyAttr)

		if (id) attr('id', id)
		if (className) attr('class', className)

		return tagName
	}

	function applyAttrsObj(attrsObj) {
		for (var k in attrsObj) {
			attr(k, attrsObj[k])
		}
	}

	function parse(markup) {
		var head = markup[0]
		var attrsObj = markup[1]
		var hasAttrs = attrsObj && attrsObj.constructor === Object
		var firstChildPos = hasAttrs ? 2 : 1
		var keyAttr = hasAttrs && attrsObj.key
		var skipAttr = hasAttrs && attrsObj.skip

		var tagName = openTag(head, keyAttr)

		if (hasAttrs) applyAttrsObj(attrsObj)

		elementOpenEnd()

		if (skipAttr) {
			skip()
		} else {
			for (var i = firstChildPos, len = markup.length; i < len; i++) {
				var node = markup[i]

				if (node === undefined) continue

				switch (node.constructor) {
					case Array:
						parse(node)
						break
					case Function:
						node(currentElement())
						break
					default:
						text(node)
				}
			}
		}

		elementClose(tagName)
	}

	return parse
})();
