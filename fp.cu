// usage:
// nvcc .\fp.cu -o fp
// fp.exe {file} {minimumSupport} {outputFile}
#include <stdio.h>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>
#include <map>
#include <algorithm>
#include <chrono>

std::vector<std::pair<std::vector<int>, int>> patterns;

// general tree struct
struct TreeNode
{
    int item;
    int count;

    TreeNode *parent;
    std::vector<TreeNode *> children;

    TreeNode(int item, int count, TreeNode *parent)
    {
        this->item = item;
        this->count = count;
        this->parent = parent;
    }

    ~TreeNode()
    {
        for (int i = 0; i < children.size(); i++)
        {
            delete children[i];
        }
    }

    void addChild(TreeNode *child)
    {
        children.push_back(child);
    }

    TreeNode *find(int item)
    {
        TreeNode *current = this;
        for (int i = 0; i < children.size(); i++)
        {
            current = children[i];
            if (current->item == item)
            {
                return current;
            }
            current = this;
        }
        return NULL;
    }

    std::pair<std::vector<int>, int> getPath()
    {
        std::vector<int> path;
        int c = count;
        TreeNode *node = this;
        while (node->parent->item != -1)
        {
            path.push_back(node->parent->item);
            node = node->parent;
        }

        std::reverse(path.begin(), path.end());

        return std::make_pair(path, c);
    }

    void deleteTree()
    {
        for (int i = 0; i < children.size(); i++)
        {
            children[i]->deleteTree();
            delete children[i];
        }
        delete this;
    }
};

std::pair<std::vector<int>, std::vector<std::vector<int>>> mapForSorting(std::string fileName, int minimumSupport)
{
    std::map<int, int> map;
    std::ifstream file(fileName);
    std::string line;

    std::vector<std::vector<int>> transactions;
    while (std::getline(file, line))
    {
        std::stringstream ss(line);
        int item;
        std::vector<int> transaction;
        while (ss >> item)
        {
            transaction.push_back(item);
            map[item]++;
        }

        transactions.push_back(transaction);
    }

    // sort map
    std::vector<std::pair<int, int>> vec;
    for (auto it = map.begin(); it != map.end(); it++)
    {
        vec.push_back(*it);
    }

    std::sort(vec.begin(), vec.end(), [](const std::pair<int, int> &a, const std::pair<int, int> &b)
              { return a.second > b.second; });

    // remove items with support less than minimum support
    for (int i = 0; i < vec.size(); i++)
    {
        if (vec[i].second < minimumSupport)
        {
            vec.erase(vec.begin() + i);
            i--;
        }
    }

    // get keys
    std::vector<int> keys;
    for (auto it = vec.begin(); it != vec.end(); it++)
    {
        keys.push_back(it->first);
    }

    // remove items that are not in the keys
    for (auto it = transactions.begin(); it != transactions.end(); it++)
    {
        for (int i = 0; i < (*it).size(); i++)
        {
            if (std::find(keys.begin(), keys.end(), (*it)[i]) == keys.end())
            {
                (*it).erase((*it).begin() + i);
                i--;
            }
        }

        std::sort((*it).begin(), (*it).end(), [&keys](int a, int b)
                  { return std::find(keys.begin(), keys.end(), a) < std::find(keys.begin(), keys.end(), b); });
    }

    // return map
    return std::make_pair(keys, transactions);
}

std::pair<TreeNode *, std::map<int, std::vector<TreeNode *>>> buildTree(std::vector<int> keys, std::vector<std::vector<int>> vec)
{
    std::map<int, std::vector<TreeNode *>> map;
    TreeNode *root = new TreeNode(-1, 0, NULL);

    int nodes = 0;
    for (int i = 0; i < vec.size(); i++)
    {
        TreeNode *node = root;
        for (int j = 0; j < vec[i].size(); j++)
        {
            // convert item to int
            int item = vec[i][j];

            TreeNode *child = node->find(item);

            // if child doesn't exist, create it
            if (child == NULL)
            {
                nodes++;
                child = new TreeNode(item, 1, node);
                node->addChild(child);
                // if item is not in the map, create a new array and point to it
                if (map.find(item) == map.end())
                {
                    std::vector<TreeNode *> arr;
                    arr.push_back(child);
                    map[item] = arr;
                }
                // if item is in the map, add child to the array
                else
                {
                    map[item].push_back(child);
                }
            }
            else
            {
                child->count++;
            }
            node = child;
        }
    }

    return std::make_pair(root, map);
}

std::pair<TreeNode *, std::map<int, std::vector<TreeNode *>>> buildVariableTree(std::vector<int> keys, std::vector<std::pair<std::vector<int>, int>> vec)
{
    std::map<int, std::vector<TreeNode *>> map;
    TreeNode *root = new TreeNode(-1, 0, NULL);

    for (int i = 0; i < vec.size(); i++)
    {
        TreeNode *node = root;
        for (int j = 0; j < vec[i].first.size(); j++)
        {
            // convert item to int
            int item = vec[i].first[j];

            TreeNode *child = node->find(item);

            // if child doesn't exist, create it
            if (child == NULL)
            {
                child = new TreeNode(item, vec[i].second, node);
                node->addChild(child);
                // if item is not in the map, create a new array and point to it
                if (map.find(item) == map.end())
                {
                    std::vector<TreeNode *> arr;
                    arr.push_back(child);
                    map[item] = arr;
                }
                // if item is in the map, add child to the array
                else
                {
                    map[item].push_back(child);
                }
            }
            else
            {
                child->count += vec[i].second;
            }
            node = child;
        }
    }

    return std::make_pair(root, map);
}

void printTree(TreeNode *root)
{
    std::vector<int> path = root->getPath().first;
    int count = root->getPath().second;
    std::cout << "(";
    for (int i = 0; i < path.size(); i++)
    {
        std::cout << path[i];
        if (i != path.size() - 1)
        {
            std::cout << " ";
        }
    }
    std::cout << ") " << count << std::endl;
    for (int i = 0; i < root->children.size(); i++)
    {
        printTree(root->children[i]);
    }
}

// tree, dict, sorting keys, base, minimum support
void mining(TreeNode *root, std::map<int, std::vector<TreeNode *>> map, std::vector<int> keys, std::vector<int> base, int minimumSupport)
{
    // base copy
    std::vector<int> baseCopy = base;
    std::vector<std::pair<std::vector<int>, int>> vec;

    for (auto it = map.begin(); it != map.end(); it++)
    {
        int count = 0;
        for (int i = 0; i < it->second.size(); i++)
        {
            count += it->second[i]->count;
            vec.push_back(std::make_pair(it->second[i]->getPath().first, it->second[i]->count));
        }

        // if count is greater than minimum support
        if (count >= minimumSupport)
        {
            // add item to base
            base.push_back(it->first);

            patterns.push_back(std::make_pair(base, count));

            // build variable tree
            std::pair<TreeNode *, std::map<int, std::vector<TreeNode *>>> tree = buildVariableTree(base, vec);
            mining(tree.first, tree.second, keys, base, minimumSupport);
            // tree.first->deleteTree();
        }

        vec.clear();
        base = baseCopy;
    }
}

int main(int argc, char *argv[])
{
    if (argc < 4)
    {
        printf("Usage: %s {file} {minimumSupport} {outputfile}\n", argv[0]);
        return 0;
    }

    // start time
    auto start = std::chrono::high_resolution_clock::now();

    std::string file = argv[1];
    int minimumSupport = atoi(argv[2]);

    // make hashmap
    std::pair<std::vector<int>, std::vector<std::vector<int>>> map = mapForSorting(file, minimumSupport);
    std::vector<int> keys = map.first;
    std::vector<std::vector<int>> transactions = map.second;

    // make tree
    std::pair<TreeNode *, std::map<int, std::vector<TreeNode *>>> tree = buildTree(keys, transactions);
    TreeNode *root = tree.first;
    std::map<int, std::vector<TreeNode *>> map2 = tree.second;

    std::vector<int> base;
    for (auto it = map2.begin(); it != map2.end(); it++)
    {
        // std::cout << it->first << std::endl;
        int count = 0;
        std::vector<std::pair<std::vector<int>, int>> vec;
        for (int i = 0; i < it->second.size(); i++)
        {
            count += it->second[i]->count;
            vec.push_back(std::make_pair(it->second[i]->getPath().first, it->second[i]->count));
        }

        // if count is greater than minimum support
        // std::cout << "count: " << count << std::endl;
        if (count >= minimumSupport)
        {
            // add item to base
            base.push_back(it->first);
            // add item to patterns
            patterns.push_back(std::make_pair(base, count));
            // build variable tree
            std::pair<TreeNode *, std::map<int, std::vector<TreeNode *>>> tree = buildVariableTree(base, vec);
            mining(tree.first, tree.second, keys, base, minimumSupport);
        }

        // empty base
        base.clear();
    }

    // delete tree
    // root->deleteTree();

    // end time
    auto end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> diff = end - start;

    // write to file
    std::ofstream outfile;
    outfile.open(argv[3]);
    outfile << "Time: " << diff.count() << " seconds" << std::endl;
    outfile << "Number of patterns: " << patterns.size() << std::endl;
    for (auto it = patterns.begin(); it != patterns.end(); it++)
    {
        for (int i = 0; i < it->first.size(); i++)
        {
            outfile << it->first[i];
            if (i != it->first.size() - 1)
            {
                outfile << " ";
            }
        }
        outfile << ": " << it->second << std::endl;
    }

    std::cout << "Time: " << diff.count() << " seconds" << std::endl;
    std::cout << "Number of patterns: " << patterns.size() << std::endl;

    return 0;
}