declare var d3: any;
import Globals from './Globals';
import Tree from './Tree';
import Node from '../testable/Node';
import State from '../testable/State';

export default class Listener {

    public static setLoadedCount() {
        $("#total").text(State.totalLoaded + "/" + Number(State.id2Node[State.rootId].decCount + 1));
    }

    public static bindListener() {

        window.addEventListener('message', event => {
            const message = event.data;

            switch (message.command) {

                case 'loadSet':
                    Globals.lv.id2Node[message.data.structure.name].children = message.data.structure.children;
                    Globals.lv.updateFromRoot();
                    Globals.lv.updateNodes([message.data.update]);
                    Globals.sendPrettyRequest();
                    break;

                case 'init':
                    // console.log(message.data);
                    Globals.lv.update(message.data.prettyAtRoot);
                    State.simpleDomainsAtRoot = message.data.simpleAtRoot.vars;

                    State.solAncestorIds = message.data.core.solAncestorIds;

                    State.totalLoaded += message.data.core.nodes.length;

                    // console.log(message.data.core.nodes);

                    for (let i = 0; i < message.data.core.nodes.length; i++) {
                        let element = message.data.core.nodes[i];
                        // console.log(element.isSolution)
                        State.addNode(element.parentId,  element);                        



                        // State.addNode(element.id, element.parentId, element.label, element.prettyLabel, element.decCount, element.isLeftChild, element.childCount, element.isSolution);
                    }
                    // console.log(State.id2Node[State.rootId]);


                    Tree.update(State.id2Node[State.rootId]);
                    Node.collapseNode(State.id2Node[State.rootId]);
                    Tree.update(State.id2Node[State.rootId]);
                    Tree.selectNode(State.rootId);
                    this.setLoadedCount();

                    break;

                case 'longestBranchingVariable':

                    // console.log(message.data);
                    // Tree.tree.nodeSize([1000, Tree.nodeHeight]);
                    Tree.tree.nodeSize([Number(message.data) * 13, Tree.nodeHeight]);
                    break;

                case 'loadNodes':

                    // console.log(message.data);

                    var parent = null;

                    message.data.forEach((element: any) => {


                        if (!State.id2Node[element.id]) {

                            // console.log("addindg " + element.id);

                            parent = State.id2Node[element.parentId];

                            if (!parent.children){
                                State.id2Node[element.parentId].children = [];
                            }

                            if (element.isLeftChild){
                                parent.children!.unshift(element);
                            }
                            else{
                                parent.children!.push(element);
                            }

                    //         State.addNode(element.nodeId, element.parentId, element.label, element.prettyLabel, element.decendantCount, element.isLeftChild);
                    //         State.id2ChildIds[element.nodeId] = element.children;
                            State.totalLoaded++;
                    //         // Globals.loadChildIds(element.nodeId);
                        }
                    });

                    // console.log(parent);

                    // Tree.update(parent);
                    Tree.update(State.id2Node[State.rootId]);

                    Tree.selectNode(State.selectedId);

                    Listener.setLoadedCount();

                    break;

                case 'simpleDomains':

                    // console.log(message.data.changedNames);    

                    message.data.vars.forEach((variable: any) => {

                        // console.log(message.data.changedNames);

                        $("#" + $.escapeSelector(variable.name)).removeClass("changed");

                        let li = $("#" + $.escapeSelector(variable.name) + " > :last-child");
                        li.text(variable.rng);

                        if (message.data.changedNames.includes(variable.name)) {
                            d3.select('[id="' + $.escapeSelector(variable.name) + '"]').classed("changed", true);
                            // $("#" + $.escapeSelector(variable.name)).toggleClass("changed");
                        }
                    });
                    break;

                case 'prettyDomains':
                    // console.log(message.data);

                    Globals.lv.setChangedExpressions(message.data.changedExpressions);
                    Globals.lv.updateNodes(message.data.vars);
                    Globals.lv.setChanged(message.data.changed);
                    break;
            }
            State.waiting = false;
        });

    }
}
